import XCTest
@testable import LGKumanda

final class WebVideoLiveTests: XCTestCase {
    @MainActor func testNativeVideoThenRestoreOriginalApp() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["LG_LIVE_VIDEO_TEST"] == "1", let raw = env["LG_VIDEO_URL"],
              let video = WebVideo.parse(["url":raw,"mime":"video/mp4","title":"LG Kumanda video kontrol testi"]) else {
            throw XCTSkip("Opt-in: opens a short test video and restores the previous TV app")
        }
        let client = TVClient()
        let tv = try XCTUnwrap(client.selected)
        print("WEB_VIDEO stage: connect")
        client.connect(to:tv)
        defer { client.disconnect() }
        let deadline = Date().addingTimeInterval(15)
        while client.state != .connected && Date() < deadline { try await Task.sleep(nanoseconds:100_000_000) }
        XCTAssertEqual(client.state,.connected)
        guard client.state == .connected else { return }
        print("WEB_VIDEO stage: connected")
        let before = try await client.request("com.webos.applicationManager/getForegroundAppInfo")
        let original = try XCTUnwrap(before["appId"] as? String)
        do {
            print("WEB_VIDEO stage: open")
            try await client.openWebVideo(video)
            XCTAssertNotNil(client.webVideoSession)
            print("WEB_VIDEO stage: viewer acknowledged")
            try await Task.sleep(nanoseconds:2_000_000_000)
            let info = try await client.request("com.webos.media/getForegroundAppInfo")
            print("WEB_VIDEO media response keys: \(info.keys.sorted())")
            try await client.controlWebVideo(.pause)
            try await client.controlWebVideo(.play)
            try await client.controlWebVideo(.stop)
            _ = try await client.request("system.launcher/launch",["id":original])
            print("WEB_VIDEO open/play/pause/stop acknowledged; original app restored.")
        } catch {
            _ = try? await client.request("system.launcher/launch",["id":original])
            throw error
        }
    }
}
