import XCTest
@testable import LGKumanda

final class ShortcutSuggestionTests: XCTestCase {
    func testDefaultsUseInstalledAppAndInputIDs() {
        let apps = [TVItem(id:"netflix",title:"Netflix"), TVItem(id:"youtube.leanback.v4",title:"YouTube"),
                    TVItem(id:"com.webos.app.browser",title:"Web Tarayıcısı"), TVItem(id:"com.tvplus.app",title:"TV+"),
                    TVItem(id:"com.webos.app.hdmi3",title:"tivibu")]
        let inputs = [TVItem(id:"HDMI_3",title:"tivibu"), TVItem(id:"HDMI_4",title:"tvp")]
        let shortcuts = TVShortcut.suggested(apps:apps,inputs:inputs)
        XCTAssertEqual(shortcuts.prefix(3).map(\.targetID), ["netflix","youtube.leanback.v4","com.webos.app.browser"])
        XCTAssertEqual(shortcuts.filter { $0.kind == .input }.map(\.targetID), ["HDMI_3","HDMI_4"])
        XCTAssertEqual(shortcuts.count,6)
        XCTAssertFalse(shortcuts.contains { $0.kind == .app && $0.targetID.hasPrefix("com.webos.app.hdmi") })
        XCTAssertEqual(TVShortcut.fromApp(apps[4], inputs:inputs).id,"input:HDMI_3")
    }
    func testMissingAppsDoNotCreateBrokenDefaults() {
        XCTAssertTrue(TVShortcut.suggested(apps:[TVItem(id:"other",title:"Other")]).isEmpty)
    }
}

@MainActor final class ShortcutPersistenceTests: XCTestCase {
    func testFavoritesStaySeparateAcrossTVsAndSurviveReload() throws {
        let name = "ShortcutsTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName:name))
        defer { defaults.removePersistentDomain(forName:name) }
        let store = ShortcutStore(defaults:defaults)
        let first = UUID(), second = UUID()
        store.seed(tv:first,apps:[TVItem(id:"netflix",title:"Netflix")])
        let custom = TVShortcut(kind:.input,targetID:"HDMI_4",title:"TVP")
        store.put(custom,tv:first)
        store.put(TVShortcut(kind:.app,targetID:"netflix",title:"Film"),tv:first)
        XCTAssertEqual(store.items(for:first).count,2)
        XCTAssertEqual(store.items(for:first).first?.title,"Film")
        XCTAssertTrue(store.items(for:second).isEmpty)
        store.reorder([custom.id,"app:netflix"],tv:first)
        XCTAssertEqual(ShortcutStore(defaults:defaults).items(for:first).first,custom)
        store.remove(custom.id,tv:first); store.remove("app:netflix",tv:first)
        store.seed(tv:first,apps:[TVItem(id:"netflix",title:"Netflix")])
        XCTAssertTrue(store.items(for:first).isEmpty,"An explicitly empty list must stay empty on reconnect")
    }
}

final class ControlRoutingTests: XCTestCase {
    func testPlatformChannelButtonsNeverCallTheTVTuner() {
        for context in [ControlContext.application,.hdmi] {
            XCTAssertEqual(ControlRouting.channel(up:true,context:context),.key(.channelUp))
            XCTAssertEqual(ControlRouting.channel(up:false,context:context),.key(.channelDown))
        }
        XCTAssertEqual(ControlRouting.channel(up:true,context:.television),.request("tv/channelUp"))
    }
    func testForegroundAndOverrideChooseTheCorrectContext() {
        XCTAssertEqual(ControlMode.automatic.context(foregroundID:"com.webos.app.hdmi4"),.hdmi)
        XCTAssertEqual(ControlMode.automatic.context(foregroundID:"com.tvplus.app"),.application)
        XCTAssertEqual(ControlMode.automatic.context(foregroundID:"com.webos.app.livetv"),.television)
        XCTAssertEqual(ControlMode.automatic.context(foregroundID:nil),.application)
        XCTAssertEqual(ControlMode.television.context(foregroundID:"com.webos.app.hdmi3"),.television)
    }
    func testPlatformPlaybackUsesRemoteKeyEvents() {
        XCTAssertEqual(ControlRouting.media(.play,context:.hdmi),.key(.play))
        XCTAssertEqual(ControlRouting.media(.fastForward,context:.application),.key(.fastForward))
        XCTAssertEqual(ControlRouting.media(.fastForward,context:.television),.request("media.controls/fastForward"))
        XCTAssertEqual(ControlRouting.appID(forInput:"HDMI_4"),"com.webos.app.hdmi4")
        XCTAssertNil(ControlRouting.appID(forInput:"OTHER"))
    }
}

final class BrowserAddressTests: XCTestCase {
    func testDomainPasteGetsHTTPSAndKeepsPathAndQuery() throws {
        XCTAssertEqual(try BrowserAddress.resolve("  example.com/search?q=tv&lang=tr\n").absoluteString,"https://example.com/search?q=tv&lang=tr")
        XCTAssertEqual(try BrowserAddress.resolve("http://192.168.1.3:8080/test").absoluteString,"http://192.168.1.3:8080/test")
        XCTAssertNotNil(try BrowserAddress.resolve("https://example.com/merhaba dünya"))
    }
    func testUnsafeSchemesCredentialsAndMalformedAddressesAreRejected() {
        for address in ["", "file:///etc/passwd", "javascript:alert(1)", "https://", "mailto:a@b.com", "https://user:secret@example.com", "https://example.com/\nother"] {
            XCTAssertThrowsError(try BrowserAddress.resolve(address),address)
        }
    }
    func testWordsBecomeGoogleSearchButAddressesStayAddresses() throws {
        XCTAssertEqual(try BrowserAddress.target("hava durumu istanbul"), .search(URL(string:"https://www.google.com/search?q=hava%20durumu%20istanbul&hl=tr&gl=tr&pws=0")!))
        XCTAssertEqual(try BrowserAddress.target("c++ & swift").url.absoluteString, "https://www.google.com/search?q=c%2B%2B%20%26%20swift&hl=tr&gl=tr&pws=0")
        XCTAssertTrue(try BrowserAddress.target("netflix").isSearch)
        XCTAssertTrue(try BrowserAddress.target("saat: 15").isSearch)
        XCTAssertTrue(try BrowserAddress.target("not a host").isSearch)
        XCTAssertEqual(try BrowserAddress.target("youtube.com"), .address(URL(string:"https://youtube.com")!))
        XCTAssertEqual(try BrowserAddress.target("localhost:8080/x").url.absoluteString, "https://localhost:8080/x")
        XCTAssertFalse(try BrowserAddress.target("192.168.1.3").isSearch)
    }
}

final class SimplinkTests: XCTestCase {
    func testOnlyInputsWithCECDeviceReportSimplink() {
        let withBox: [String: Any] = ["id": "HDMI_4", "subList": [["id": "SIMPLINK", "osdName": "Tivibu Android", "portId": 4]]]
        XCTAssertEqual(TVProtocol.simplinkName(withBox), "Tivibu Android")
        XCTAssertNil(TVProtocol.simplinkName(["id": "HDMI_3", "subList": []]))
        XCTAssertNil(TVProtocol.simplinkName(["id": "HDMI_1"]))
        XCTAssertEqual(TVProtocol.simplinkName(["subList": [["id": "SIMPLINK", "osdName": " "]]]), "HDMI cihazı")
    }
}

final class PointerJumpTests: XCTestCase {
    func testJumpIsSplitIntoProtocolSizedMovesThatSumToTarget() {
        let steps = PointerJump.steps(dx: 100, dy: -45)
        XCTAssertTrue(steps.allSatisfy { abs($0.0) <= 32 && abs($0.1) <= 32 })
        XCTAssertEqual(steps.reduce(0) { $0 + $1.0 }, 100)
        XCTAssertEqual(steps.reduce(0) { $0 + $1.1 }, -45)
        XCTAssertTrue(PointerJump.steps(dx: 0, dy: 0).isEmpty)
        XCTAssertEqual(PointerJump.steps(dx: 99_999, dy: 0).reduce(0) { $0 + $1.0 }, PointerJump.limit)
    }
}

final class WebFocusTests: XCTestCase {
    func testScriptSurvivesBeingJoinedIntoOneJavascriptURL() throws {
        let source = WebFocus.script.replacingOccurrences(of: "https?:", with: "")
        XCTAssertFalse(source.contains("//"), "A // comment would swallow the rest of the one-line script")
        XCTAssertFalse(WebFocus.script.contains("%"))
        XCTAssertFalse(WebFocus.script.contains("#"))
        let url = WebFocus.url(.down)
        XCTAssertTrue(url.hasPrefix("javascript:"))
        XCTAssertFalse(url.contains(" ") || url.contains("\n") || url.contains("#"))
        XCTAssertTrue(url.removingPercentEncoding!.hasSuffix("('down')"))
    }
    func testOnlyArrowsAndOKAreRouted() {
        XCTAssertEqual(WebFocus.action(for: .left), .left)
        XCTAssertEqual(WebFocus.action(for: .enter), .arm)
        XCTAssertNil(WebFocus.action(for: .back))
        XCTAssertNil(WebFocus.action(for: .play))
    }
}
