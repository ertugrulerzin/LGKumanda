import XCTest
@testable import LGKumanda

/// Opt-in: opens a Mac-hosted page on the TV and records which pointer messages reach the page (incl. a cross-origin iframe).
final class ClickDiagnosticTests: XCTestCase {
    @MainActor func testWhichPointerMessagesClickInBrowser() async throws {
        guard ProcessInfo.processInfo.environment["LG_CLICK_TEST"] == "1" else { throw XCTSkip("Opt-in") }
        let host = "http://192.168.1.111:8771"
        func mark(_ name: String) async { _ = try? await URLSession.shared.data(from: URL(string: "\(host)/hit?MARK_\(name)")!) }
        func sleep(_ s: Double) async throws { try await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
        let client = TVClient()
        let tv = try XCTUnwrap(client.selected)
        client.connect(to: tv)
        defer { client.disconnect() }
        let by = Date().addingTimeInterval(15)
        while (client.state != .connected || !client.pointerReady) && Date() < by { try await sleep(0.1) }
        await client.refreshLibrary()
        let original = try await client.request("com.webos.applicationManager/getForegroundAppInfo")["appId"] as? String
        try await client.openBrowser(URL(string: "\(host)/")!)
        try await sleep(8)
        func showPointer() async throws {
            for _ in 0..<6 { client.pointerMessage("type:move\ndx:10\ndy:5\ndown:0\n\n"); try await sleep(0.05) }
            try await sleep(0.8)
        }
        let app = try XCTUnwrap(client.browserAppID)
        func js(_ code: String) async { _ = try? await client.request("system.launcher/launch", ["id": app, "params": ["target": "javascript:void(" + code + ")"]]) }
        client.key(.down); try await sleep(2)
        await js("new Image().src='http://192.168.1.111:8771/hit?DBG_cur_'+(window.__lgnav&&__lgnav.cur?__lgnav.cur.tagName:'none')+'_active_'+document.activeElement.tagName+'_hasFocus_'+document.hasFocus()")
        try await sleep(1.5)
        client.key(.enter); try await sleep(3)
        await js("new Image().src='http://192.168.1.111:8771/hit?DBG2_armed_'+__lgnav.armed+'_active_'+document.activeElement.tagName+'_hasFocus_'+document.hasFocus()+'_href_'+encodeURIComponent(location.href)")
        try await sleep(1.5)
        await mark("END")
        if let original, let input = client.inputs.first(where: { ControlRouting.appID(forInput: $0.id) == original }) {
            try? await client.switchInput(input.id)
        } else if let original { try? await client.launchApp(original) }
    }
}
