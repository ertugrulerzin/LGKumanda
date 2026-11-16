import XCTest
@testable import LGKumanda

final class ProtocolTests: XCTestCase {
    func testOnlyPrivateIPv4HostsCanReceivePairingCredentials() {
        for host in ["192.168.1.3", "10.0.0.1", "172.16.0.1", "172.31.255.254", "169.254.1.1"] {
            XCTAssertTrue(TVProtocol.validHost(host), host)
        }
        for host in ["8.8.8.8", "127.0.0.1", "172.15.0.1", "172.32.0.1", "192.168.1.999", "192..1.3", "192.168.1.3:3001", "https://192.168.1.3", "tv.example.com", ""] {
            XCTAssertFalse(TVProtocol.validHost(host), host)
        }
    }
    func testRegistrationUsesNeutralManifestAndOptionalSavedKey() throws {
        let fresh = try XCTUnwrap(TVProtocol.registration(key: nil)["payload"] as? [String: Any])
        XCTAssertNil(fresh["client-key"])
        XCTAssertEqual(fresh["pairingType"] as? String, "PROMPT")
        let manifest = try XCTUnwrap(fresh["manifest"] as? [String: Any])
        XCTAssertNil(manifest["signatures"])
        XCTAssertNil(manifest["signed"])
        let returning = try XCTUnwrap(TVProtocol.registration(key: "test-key")["payload"] as? [String: Any])
        XCTAssertEqual(returning["client-key"] as? String, "test-key")
    }
    func testTextPayloadPreservesUnicodeAndEscapes() throws {
        let text = "İyi akşamlar 👋\n\"LG\" \\"
        let message = TVProtocol.request(id: "42", uri: "com.webos.service.ime/insertText", payload: ["text": text, "replace": 0])
        let bytes = try JSONSerialization.data(withJSONObject: message)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(decoded["uri"] as? String, "ssap://com.webos.service.ime/insertText")
        XCTAssertEqual((decoded["payload"] as? [String: Any])?["text"] as? String, text)
        XCTAssertEqual(decoded["type"] as? String, "request")
        XCTAssertEqual(TVProtocol.request(id: "v", uri: "audio/getVolume", subscribe: true)["type"] as? String, "subscribe")
    }
    func testRemoteKeysUseDoubleNewlineFraming() {
        XCTAssertEqual(RemoteKey.home.wireMessage, "type:button\nname:HOME\n\n")
        XCTAssertEqual(Set(RemoteKey.allCases.map(\.rawValue)).count, RemoteKey.allCases.count)
        XCTAssertEqual(RemoteKey.zero.rawValue, "0")
    }
    func testWakePacketContainsSixFFBytesAndSixteenMACCopies() throws {
        let packet = try WakeOnLAN.packet(mac: "AA:bb:CC:dd:EE:ff")
        XCTAssertEqual(packet.count, 102)
        XCTAssertEqual(Array(packet.prefix(6)), Array(repeating: 255, count: 6))
        for offset in stride(from: 6, to: 102, by: 6) {
            XCTAssertEqual(Array(packet[offset..<offset + 6]), [170, 187, 204, 221, 238, 255])
        }
        XCTAssertEqual(try WakeOnLAN.packet(mac: "AA-BB-CC-DD-EE-FF"), packet)
    }
    func testMalformedMACNeverSendsPacket() {
        for mac in ["", "AA:BB:CC:DD:EE", "GG:BB:CC:DD:EE:FF", "A:BB:CC:DD:EE:FF", "AA:BB:CC:DD:EE:FF:"] {
            XCTAssertThrowsError(try WakeOnLAN.packet(mac: mac), mac)
        }
    }
    func testWakeUsesTheActiveNICAndActualSubnet() throws {
        let info: [String: Any] = ["wiredInfo": ["macAddress": "20:30:40:50:60:70"], "wifiInfo": ["macAddress": "aa-bb-cc-dd-ee-02"]]
        let status: [String: Any] = ["wired": ["state": "disconnected"], "wifi": ["state": "connected", "ipAddress": "192.168.5.40", "netmask": "255.255.252.0"]]
        let identity = try XCTUnwrap(WakeOnLAN.networkIdentity(info: info, status: status, host: "192.168.5.40"))
        XCTAssertEqual(identity.mac, "AA:BB:CC:DD:EE:02")
        XCTAssertEqual(identity.broadcast, "192.168.7.255")
        XCTAssertNil(WakeOnLAN.networkIdentity(info: info, status: [:], host: "192.168.5.40"))
        XCTAssertNil(WakeOnLAN.networkIdentity(info: info, status: status, host: "192.168.5.41"))
        XCTAssertNil(WakeOnLAN.networkIdentity(info: ["wifiInfo": ["macAddress": "00:00:00:00:00:00"]], status: [:], host: "192.168.5.40"))
    }
    func testWakeTargetsIncludeUnicastAndMatchingSubnetBroadcastOnly() throws {
        let subnets = [LocalSubnet(address: "192.168.5.10", mask: "255.255.252.0"), LocalSubnet(address: "10.0.0.2", mask: "255.255.255.0")]
        XCTAssertEqual(try WakeOnLAN.targets(host: "192.168.5.40", broadcast: "255.255.255.255", subnets: subnets), ["192.168.5.40", "192.168.7.255", "255.255.255.255"])
        XCTAssertThrowsError(try WakeOnLAN.targets(host: "192.168.5.40", broadcast: "8.8.8.8", subnets: subnets))
        XCTAssertThrowsError(try WakeOnLAN.targets(host: "8.8.8.8", broadcast: "255.255.255.255", subnets: subnets))
        XCTAssertNil(LocalSubnet(address: "192.168.5.10", mask: "255.0.255.0").broadcast)
        XCTAssertNil(LocalSubnet(address: "192.168.5.10", mask: "255.255.255.254").broadcast)
    }
    func testCredentialsRoundTripAndDelete() {
        let account = "test.\(UUID())"
        defer { KeychainStore.delete(account) }
        XCTAssertNil(KeychainStore.read(account))
        XCTAssertTrue(KeychainStore.save("first", account: account))
        XCTAssertTrue(KeychainStore.save("updated", account: account))
        XCTAssertEqual(KeychainStore.read(account), "updated")
        KeychainStore.delete(account)
        XCTAssertNil(KeychainStore.read(account))
    }
    @MainActor func testDisconnectedRequestsFailImmediately() async {
        let client = TVClient()
        do { _ = try await client.request("audio/volumeUp"); XCTFail("Expected connection error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("bağlan")) }
    }
}

final class DiscoveryTests: XCTestCase {
    func testOnlyLGLocalLocationsAreAccepted() {
        let prefix = "HTTP/1.1 200 OK\r\nST: urn:lge-com:service:webos-second-screen:1\r\n"
        XCTAssertEqual(TVDiscovery.location(from: prefix + "LOCATION: http://192.168.1.3:1311/\r\n"), "http://192.168.1.3:1311/")
        XCTAssertNil(TVDiscovery.location(from: prefix + "LOCATION: http://8.8.8.8/\r\n"))
        XCTAssertNil(TVDiscovery.location(from: prefix + "LOCATION: http://user:pass@192.168.1.3/\r\n"))
        XCTAssertNil(TVDiscovery.location(from: "LOCATION: http://192.168.1.3/\r\n"))
    }
}

final class AudioStatusTests: XCTestCase {
    func testFlatAndNestedFirmwarePayloads() {
        XCTAssertEqual(TVProtocol.audioStatus(["volume": 12, "muted": true]).volume, 12)
        XCTAssertEqual(TVProtocol.audioStatus(["volume": 12, "muted": true]).muted, true)
        let nested: [String: Any] = ["volumeStatus": ["volume": 24, "mute": false]]
        XCTAssertEqual(TVProtocol.audioStatus(nested).volume, 24)
        XCTAssertEqual(TVProtocol.audioStatus(nested).muted, false)
        XCTAssertNil(TVProtocol.audioStatus(["error": "not supported"]).volume)
    }
}

final class PointerFilterTests: XCTestCase {
    func testSmallMovementsAccumulateWithoutLosingPrecision() {
        var filter = PointerDeltaFilter()
        var total = 0
        for _ in 0..<4 { total += filter.move(dx: 0.25, dy: 0, gain: 1).0 }
        XCTAssertEqual(total, 1)
    }
    func testLargeMovementIsBoundedAndDoesNotLeaveBacklog() {
        var filter = PointerDeltaFilter()
        let jump = filter.move(dx: 10000, dy: -10000, gain: 1)
        XCTAssertEqual(jump.0, 32); XCTAssertEqual(jump.1, -32)
        let stopped = filter.move(dx: 0, dy: 0, gain: 1)
        XCTAssertEqual(stopped.0, 0); XCTAssertEqual(stopped.1, 0)
    }
    func testFingerLiftAndInvalidInputCannotReanchorPointer() {
        var filter = PointerDeltaFilter()
        _ = filter.move(dx: 0.8, dy: -0.8, gain: 1)
        filter = PointerDeltaFilter()
        XCTAssertEqual(filter.move(dx: 0, dy: 0, gain: 1).0, 0)
        XCTAssertEqual(filter.move(dx: .nan, dy: .infinity, gain: 1).0, 0)
    }
}
