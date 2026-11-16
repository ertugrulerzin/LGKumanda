import XCTest
@testable import LGKumanda

final class AddressRecoveryTests: XCTestCase {
    private let pin = String(repeating: "a", count: 64)
    private let otherPin = String(repeating: "b", count: 64)

    private let deviceUUID = "edf365be-1c48-4995-824c-6ee1bf1b65a4"
    private func television(name: String, host: String) -> Television {
        var tv = Television(name: name, host: host)
        tv.deviceUUID = deviceUUID
        return tv
    }
    func testChangedIPKeepsIdentityAndWakeSettingsWhileIgnoringReassignedOldIP() throws {
        var saved = television(name: "Salon", host: "192.168.1.3")
        saved.mac = "20:30:40:50:60:70"
        saved.broadcast = "192.168.1.255"
        let oldAddressNowAnotherTV = television(name: "Salon", host: saved.host)
        let moved = television(name: "LG webOS TV", host: "192.168.1.44")
        let result = TVAddressRecovery.resolve(saved, fingerprint: pin,
            candidates: [oldAddressNowAnotherTV, moved],
            fingerprints: [saved.host: otherPin, moved.host: pin])
        guard case .found(let updated) = result else { return XCTFail("Expected recovery") }
        XCTAssertEqual(updated.id, saved.id)
        XCTAssertEqual(updated.host, moved.host)
        XCTAssertEqual(updated.name, saved.name)
        XCTAssertEqual(updated.mac, saved.mac)
        XCTAssertEqual(updated.broadcast, saved.broadcast)
        XCTAssertEqual(updated.secure, saved.secure)
        XCTAssertEqual(updated.deviceUUID, saved.deviceUUID)
        XCTAssertEqual(saved.host, "192.168.1.3", "Resolution must not prematurely persist the candidate")
    }
    func testMatchingNamesAndLGBrandCannotReplaceThePairedTV() {
        let saved = television(name: "Salon", host: "192.168.1.3")
        let impostor = television(name: saved.name, host: "192.168.1.44")
        XCTAssertEqual(TVAddressRecovery.resolve(saved, fingerprint: pin,
            candidates: [impostor], fingerprints: [impostor.host: otherPin]), .notFound)
        XCTAssertEqual(TVAddressRecovery.resolve(saved, fingerprint: pin,
            candidates: [impostor], fingerprints: [:]), .notFound)
    }
    func testDifferentLGTVWithSharedCertificateCannotClaimTheSavedIdentity() {
        let saved = television(name: "Salon", host: "192.168.1.3")
        var other = television(name: "Salon", host: saved.host)
        other.deviceUUID = "09c32aac-ddb8-409e-95dd-df05f2d6f746"
        let moved = television(name: "LG TV", host: "192.168.1.44")
        let result = TVAddressRecovery.resolve(saved, fingerprint: pin, candidates: [other, moved],
            fingerprints: [other.host: pin, moved.host: pin])
        guard case .found(let actual) = result else { return XCTFail("Expected UUID match") }
        XCTAssertEqual(actual.host, moved.host)
        var legacy = saved; legacy.deviceUUID = nil
        XCTAssertEqual(TVAddressRecovery.resolve(legacy, fingerprint: pin, candidates: [moved],
            fingerprints: [moved.host: pin]), .notFound)
    }
    func testHelloUUIDParsingAndLegacyMetadataMigration() throws {
        let hello = Data("{\"type\":\"hello\",\"payload\":{\"deviceUUID\":\"EDF365BE-1C48-4995-824C-6EE1BF1B65A4\"}}".utf8)
        XCTAssertEqual(TVIdentityProbe.deviceUUID(from: hello), deviceUUID)
        for json in ["{}", "{\"type\":\"registered\",\"payload\":{\"deviceUUID\":\"\(deviceUUID)\"}}", "{\"type\":\"hello\",\"payload\":{\"deviceUUID\":\"not-a-uuid\"}}"] {
            XCTAssertNil(TVIdentityProbe.deviceUUID(from: Data(json.utf8)))
        }
        let old = Data("{\"id\":\"EDF365BE-1C48-4995-824C-6EE1BF1B65A4\",\"name\":\"Salon\",\"host\":\"192.168.1.3\",\"secure\":true,\"mac\":\"\",\"broadcast\":\"255.255.255.255\"}".utf8)
        let decoded = try JSONDecoder().decode(Television.self, from: old)
        XCTAssertNil(decoded.deviceUUID)
        XCTAssertEqual(decoded.host, "192.168.1.3")
    }
    func testSharedCertificatesAreAmbiguousAndPublicAddressesAreRejected() {
        let saved = television(name: "Salon", host: "192.168.1.3")
        let first = television(name: "LG TV", host: "192.168.1.44")
        let second = television(name: "LG TV", host: "192.168.1.45")
        XCTAssertEqual(TVAddressRecovery.resolve(saved, fingerprint: pin,
            candidates: [first, second], fingerprints: [first.host: pin, second.host: pin]), .ambiguous)
        let publicDevice = television(name: "LG TV", host: "8.8.8.8")
        XCTAssertEqual(TVAddressRecovery.resolve(saved, fingerprint: pin,
            candidates: [publicDevice], fingerprints: [publicDevice.host: pin]), .notFound)
        XCTAssertEqual(TVAddressRecovery.resolve(saved, fingerprint: "",
            candidates: [first], fingerprints: [first.host: ""]), .notFound)
        var insecure = saved; insecure.secure = false
        XCTAssertEqual(TVAddressRecovery.resolve(insecure, fingerprint: pin,
            candidates: [first], fingerprints: [first.host: pin]), .notFound)
    }
    @MainActor func testManualDiscoveryReusesSavedUUIDAndCredentialsAtNewAddress() throws {
        let suite = "LGAddressRecoveryTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let saved = television(name: "Salon", host: "192.168.1.3")
        defer { KeychainStore.delete("cert.\(saved.id)"); KeychainStore.delete("key.\(saved.id)") }
        XCTAssertTrue(KeychainStore.save(pin, account: "cert.\(saved.id)"))
        XCTAssertTrue(KeychainStore.save("test-pairing-key", account: "key.\(saved.id)"))
        preferences.set(try JSONEncoder().encode([saved]), forKey: "televisions")
        let client = TVClient(preferences: preferences)
        let candidate = television(name: "LG webOS TV", host: "192.168.1.44")
        let matched = try XCTUnwrap(client.savedTelevision(for: candidate,
            candidates: [candidate], fingerprints: [candidate.host: pin]))
        XCTAssertEqual(matched.id, saved.id)
        XCTAssertEqual(matched.host, candidate.host)
        XCTAssertEqual(client.televisions.first?.host, saved.host)
        XCTAssertEqual(KeychainStore.read("key.\(matched.id)"), "test-pairing-key")
        var newTVAtOldIP = candidate; newTVAtOldIP.host = saved.host
        newTVAtOldIP.deviceUUID = "09c32aac-ddb8-409e-95dd-df05f2d6f746"
        XCTAssertNil(client.savedTelevision(for: newTVAtOldIP, candidates: [newTVAtOldIP], fingerprints: [newTVAtOldIP.host: pin]))
        let second = television(name: "LG TV", host: "192.168.1.45")
        XCTAssertNil(client.savedTelevision(for: candidate, candidates: [candidate, second],
            fingerprints: [candidate.host: pin, second.host: pin]))
    }
    @MainActor func testReassignedOldAddressStartsRecoveryWithoutReplacingSavedRecord() async throws {
        let suite = "LGAddressRecoveryTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let saved = television(name: "Salon", host: "192.168.1.3")
        defer { KeychainStore.delete("cert.\(saved.id)"); KeychainStore.delete("key.\(saved.id)") }
        XCTAssertTrue(KeychainStore.save(pin, account: "cert.\(saved.id)"))
        XCTAssertTrue(KeychainStore.save("test-pairing-key", account: "key.\(saved.id)"))
        preferences.set(try JSONEncoder().encode([saved]), forKey: "televisions")
        var scans = 0
        let client = TVClient(preferences: preferences,
            identityReader: { _, _ in "09c32aac-ddb8-409e-95dd-df05f2d6f746" },
            addressFinder: { tv, _ in
                XCTAssertEqual(tv.id, saved.id)
                scans += 1
                return .notFound
            })
        defer { client.disconnect() }
        client.connect(to: saved)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(scans, 1)
        XCTAssertEqual(client.state, .disconnected)
        XCTAssertEqual(client.televisions.first?.host, saved.host)
        XCTAssertEqual(KeychainStore.read("key.\(saved.id)"), "test-pairing-key")
    }
    @MainActor func testUserCancellationIgnoresAStaleRecoveryResult() async throws {
        let suite = "LGAddressRecoveryTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let saved = television(name: "Salon", host: "192.168.1.3")
        defer { KeychainStore.delete("cert.\(saved.id)") }
        XCTAssertTrue(KeychainStore.save(pin, account: "cert.\(saved.id)"))
        preferences.set(try JSONEncoder().encode([saved]), forKey: "televisions")
        var continuation: CheckedContinuation<TVAddressRecovery.Result, Never>?
        let client = TVClient(preferences: preferences, identityReader: { _, _ in nil },
            addressFinder: { _, _ in await withCheckedContinuation { continuation = $0 } })
        defer { client.disconnect() }
        client.connect(to: saved)
        for _ in 0..<30 { if continuation != nil { break }; await Task.yield() }
        XCTAssertNotNil(continuation)
        client.disconnect()
        var moved = saved; moved.host = "192.168.1.44"
        continuation?.resume(returning: .found(moved))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(client.state, .disconnected)
        XCTAssertEqual(client.selected?.host, saved.host)
        XCTAssertEqual(client.televisions.first?.host, saved.host)
    }
    @MainActor func testFailedRecoveredCandidateDoesNotLoopOrPersistUnconfirmedIP() async throws {
        let suite = "LGAddressRecoveryTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let saved = television(name: "Salon", host: "192.168.1.3")
        var moved = saved; moved.host = "192.168.1.44"
        defer { KeychainStore.delete("cert.\(saved.id)") }
        XCTAssertTrue(KeychainStore.save(pin, account: "cert.\(saved.id)"))
        preferences.set(try JSONEncoder().encode([saved]), forKey: "televisions")
        var scans = 0
        let client = TVClient(preferences: preferences, identityReader: { _, _ in nil },
            addressFinder: { _, _ in scans += 1; return .found(moved) })
        defer { client.disconnect() }
        client.connect(to: saved)
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(scans, 1)
        XCTAssertEqual(client.state, .disconnected)
        XCTAssertEqual(client.televisions.first?.host, saved.host)
        let persisted = try JSONDecoder().decode([Television].self, from: XCTUnwrap(preferences.data(forKey: "televisions")))
        XCTAssertEqual(persisted.first?.host, saved.host)
    }
    @MainActor func testCancelledRecoveryDoesNotStartAnotherScan() async {
        let saved = television(name: "Salon", host: "192.168.1.3")
        let task = Task { await TVAddressRecovery.find(saved, fingerprint: pin) }
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result, .cancelled)
    }
}
