import XCTest
import WebKit
@testable import LGKumanda

final class WebVideoTests: XCTestCase {
    func testPlayableAddressesPreserveSignedQueriesAndInferFormat() throws {
        let hls = try XCTUnwrap(WebVideo.parse(["url":"https://cdn.example.com/live/MASTER.M3U8?token=test-token", "title":"  Film  "]))
        XCTAssertEqual(hls.mimeType,"application/vnd.apple.mpegurl")
        XCTAssertEqual(hls.title,"Film")
        XCTAssertEqual(hls.openPayload["target"] as? String,"https://cdn.example.com/live/MASTER.M3U8?token=test-token")
        XCTAssertEqual(hls.openPayload["loop"] as? Bool,false)
        let mp4 = try XCTUnwrap(WebVideo.parse(["url":"https://cdn.example.com/stream?id=1", "mime":"video/mp4; codecs=avc1"]))
        XCTAssertEqual(mp4.mimeType,"video/mp4")
        XCTAssertEqual(mp4.title,"Web videosu")
    }
    func testUnsafeAndUnknownSourcesAreNotOfferedToTV() {
        for url in ["blob:https://example.com/a","data:video/mp4;base64,AA==","file:///tmp/video.mp4","javascript:alert(1)",
                    "https://user:password@example.com/video.mp4","https:///","https://example.com/page.html","https://example.com/video.mp4\n"] {
            XCTAssertNil(WebVideo.parse(["url":url]),url)
        }
        XCTAssertNil(WebVideo.parse(["url":String(repeating:"a",count:8193)]))
    }
    @MainActor func testCatalogDeduplicatesBoundsAndResetsOnNavigation() {
        let catalog = WebVideoCatalog()
        for _ in 0..<5 { catalog.receive(["url":"https://example.com/film.mp4"]) }
        XCTAssertEqual(catalog.videos.count,1)
        for i in 0..<60 { catalog.receive(["url":"https://example.com/film\(i).mp4"]) }
        XCTAssertEqual(catalog.videos.count,32)
        catalog.reset(); XCTAssertTrue(catalog.videos.isEmpty)
    }
    @MainActor func testDiscoveryFindsMainDocumentAndIframeSourcesWithoutPlaying() async throws {
        let catalog = WebVideoCatalog()
        let received = expectation(description:"main and iframe video discovered")
        received.expectedFulfillmentCount = 2
        let bridge = VideoDiscoveryBridge { body in
            let oldCount = catalog.videos.count
            catalog.receive(body)
            if catalog.videos.count > oldCount { received.fulfill() }
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(bridge,name:"videoSource")
        config.userContentController.addUserScript(WKUserScript(source:WebVideoDiscovery.script,injectionTime:.atDocumentStart,forMainFrameOnly:false))
        let web = WKWebView(frame:.zero,configuration:config)
        defer { web.stopLoading(); config.userContentController.removeScriptMessageHandler(forName:"videoSource") }
        web.loadHTMLString("""
        <title>Test filmi</title><video preload="none"><source src="https://example.com/movie.mp4" type="video/mp4"></video>
        <iframe srcdoc="<video preload='none'><source src='https://example.com/player.m3u8' type='application/vnd.apple.mpegurl'></video>"></iframe>
        """,baseURL:URL(string:"https://example.com"))
        await fulfillment(of:[received],timeout:10)
        XCTAssertEqual(Set(catalog.videos.map(\.format)),["MP4","HLS"])
        let playing = try await web.evaluateJavaScript("!document.querySelector('video').paused") as? Bool
        XCTAssertEqual(playing,false)
    }
}

@MainActor private final class VideoDiscoveryBridge: NSObject, WKScriptMessageHandler {
    let receive: (Any) -> Void
    init(_ receive: @escaping (Any) -> Void) { self.receive = receive }
    func userContentController(_ userContentController: WKUserContentController,didReceive message: WKScriptMessage) { receive(message.body) }
}
