import XCTest
@testable import LGKumanda

final class LiveTVTests: XCTestCase {
    @MainActor func testLaunchShortcutsAndBrowserURLThenRestoreSource() async throws {
        guard ProcessInfo.processInfo.environment["LG_LIVE_LAUNCH_TEST"] == "1" else { throw XCTSkip("Opt-in test temporarily launches TV apps and restores the source") }
        let client = TVClient()
        let tv = try XCTUnwrap(client.selected)
        client.connect(to: tv)
        defer { client.disconnect() }
        let connectedBy = Date().addingTimeInterval(15)
        while client.state != .connected && Date() < connectedBy { try await Task.sleep(nanoseconds:100_000_000) }
        XCTAssertEqual(client.state,.connected)
        await client.refreshLibrary()
        let foreground = try await client.request("com.webos.applicationManager/getForegroundAppInfo")
        let original = try XCTUnwrap(foreground["appId"] as? String)
        let restore: TVShortcut
        if let input = client.inputs.first(where:{ ControlRouting.appID(forInput:$0.id) == original }) {
            restore = TVShortcut(kind:.input,targetID:input.id,title:input.title)
        } else if let app = client.apps.first(where:{ $0.id == original }) {
            restore = TVShortcut.fromApp(app,inputs:client.inputs)
        } else { throw XCTSkip("Original TV source cannot be safely restored") }
        func waitForApp(_ id: String) async throws {
            let deadline = Date().addingTimeInterval(8)
            repeat {
                let state = try await client.request("com.webos.applicationManager/getForegroundAppInfo")
                if state["appId"] as? String == id { return }
                try await Task.sleep(nanoseconds:250_000_000)
            } while Date() < deadline
            throw TVClient.Failure.message("TV did not switch to expected app: \(id)")
        }
        do {
            let defaults = TVShortcut.suggested(apps:client.apps)
            for shortcut in defaults.prefix(3) {
                try await client.activate(shortcut)
                try await waitForApp(shortcut.targetID)
            }
            try await client.openBrowser(try BrowserAddress.resolve("https://example.com"))
            try await waitForApp(try XCTUnwrap(client.browserAppID))
            try await Task.sleep(nanoseconds:2_000_000_000)
            try await client.activate(restore)
            try await waitForApp(original)
            let restoredBy = Date().addingTimeInterval(10)
            var stableSince = Date()
            while Date().timeIntervalSince(stableSince) < 3 && Date() < restoredBy {
                let state = try await client.request("com.webos.applicationManager/getForegroundAppInfo")
                if state["appId"] as? String != original {
                    try await client.activate(restore)
                    stableSince = Date()
                }
                try await Task.sleep(nanoseconds:250_000_000)
            }
            try await waitForApp(original)
            print("LIVE_LAUNCH verified: Netflix, YouTube, browser URL command; restored original source \(original). HDMI box CEC response was not asserted.")
        } catch {
            try? await client.activate(restore)
            throw error
        }
    }
    @MainActor func testLibrarySnapshotReadOnly() async throws {
        guard ProcessInfo.processInfo.environment["LG_LIVE_TV_TEST"] == "1" else { throw XCTSkip("Requires paired TV") }
        let client = TVClient()
        let tv = try XCTUnwrap(client.selected)
        client.connect(to: tv)
        defer { client.disconnect() }
        let deadline = Date().addingTimeInterval(15)
        while client.state != .connected && Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(client.state, .connected)
        await client.refreshLibrary()
        let foreground = try await client.request("com.webos.applicationManager/getForegroundAppInfo")
        let reported = foreground["appId"] as? String
        let subscribedBy = Date().addingTimeInterval(3)
        while client.foregroundAppID != reported && Date() < subscribedBy { try await Task.sleep(nanoseconds:100_000_000) }
        XCTAssertEqual(client.foregroundAppID, reported, "Foreground subscription must identify HDMI and native apps")
        let snapshot: [String: Any] = ["apps":client.apps.map { ["id":$0.id,"title":$0.title] },
                                      "inputs":client.inputs.map { ["id":$0.id,"title":$0.title] }, "foreground":foreground]
        let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "TV library"; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testPairedTVReadOnlyIntegration() async throws {
        guard ProcessInfo.processInfo.environment["LG_LIVE_TV_TEST"] == "1" else {
            throw XCTSkip("Opt in with TEST_RUNNER_LG_LIVE_TV_TEST=1; requires an already paired TV.")
        }
        let client = TVClient()
        let tv = try XCTUnwrap(client.selected, "Pair a TV in the app before this test.")
        XCTAssertNotNil(KeychainStore.read("key.\(tv.id)"))
        client.connect(to: tv)
        defer { client.disconnect() }
        let deadline = Date().addingTimeInterval(15)
        while client.state != .connected && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(client.state, .connected, client.error ?? "No connection")
        let volume = try await client.request("audio/getVolume")
        XCTAssertNotNil(TVProtocol.audioStatus(volume).volume)
        await client.refreshLibrary()
        XCTAssertFalse(client.apps.isEmpty, "Installed apps must load")
        XCTAssertFalse(client.inputs.isEmpty, "Inputs must load")
        XCTAssertTrue(client.pointerReady, client.notice ?? "Pointer socket unavailable")
        let discovery = TVDiscovery()
        let (expectedData, _) = try await URLSession.shared.data(from: URL(string: "http://\(tv.host):1311/")!)
        let expectedIdentity = try XCTUnwrap(TVDiscovery.deviceDescription(from: expectedData)?.identity)
        await discovery.search(useMulticast: false)
        var identities: [String] = []
        for discovered in discovery.found {
            let (data, _) = try await URLSession.shared.data(from: URL(string: "http://\(discovered.host):1311/")!)
            identities.append(try XCTUnwrap(TVDiscovery.deviceDescription(from: data)?.identity))
        }
        XCTAssertTrue(identities.contains(expectedIdentity), "TV must be discovered without multicast, regardless of network interface")
        XCTAssertEqual(Set(identities).count, identities.count, "One TV should only appear once")
        print("LIVE_TV completed: TLS reconnect, saved pairing, volume read, \(client.apps.count) apps, \(client.inputs.count) inputs, \(client.channels.count) channels, pointer socket ready. No state-changing commands sent.")
    }
}
