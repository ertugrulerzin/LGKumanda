import XCTest

/// Produces App Store screenshots from the DEBUG-only preview state (sample TV and box, nothing on the network).
/// Run on a 6.9-inch iPhone simulator; images are attached to the test result.
final class ScreenshotTests: XCTestCase {
    func testAppStoreScreenshots() {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_SCREENSHOTS"] = "1"
        app.launchArguments += ["-androidTVBoxes", "<5b7b226964223a202236463146324133422d303030302d343030302d383030302d303030303030303030303031222c2022686f7374223a20223139322e302e322e3131222c20226e616d65223a2022416e64726f6964205456222c2022696e7075744944223a202248444d495f33222c2022706169726564223a20747275657d5d>", "-androidTVBoxes.active", "6F1F2A3B-0000-4000-8000-000000000001"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteTarget.box"].waitForExistence(timeout: 8))
        sleep(1)
        shot(app, "2-kutu-kumanda")
        app.swipeUp(); sleep(1)
        shot(app, "3-kutu-rakamlar")
        app.swipeDown(); app.swipeDown(); sleep(1)
        app.buttons["remoteTarget.tv"].tap(); sleep(1)
        shot(app, "1-tv-kumanda")
        app.tabBars.buttons["Uygulamalar"].tap(); sleep(1)
        shot(app, "4-uygulamalar")
        app.tabBars.buttons["Klavye"].tap(); sleep(1)
        shot(app, "5-klavye")
        app.tabBars.buttons["Cihazlar"].tap(); sleep(1)
        shot(app, "6-cihazlar")
    }
    /// Walks through the app at a viewer's pace for a screen recording (run with simctl recordVideo).
    func testDemoVideo() {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_SCREENSHOTS"] = "1"
        app.launchArguments += ["-androidTVBoxes", "<5b7b226964223a202236463146324133422d303030302d343030302d383030302d303030303030303030303031222c2022686f7374223a20223139322e302e322e3131222c20226e616d65223a2022416e64726f6964205456222c2022696e7075744944223a202248444d495f33222c2022706169726564223a20747275657d5d>", "-androidTVBoxes.active", "6F1F2A3B-0000-4000-8000-000000000001"]
        app.launch()
        XCTAssertTrue(app.buttons["remoteTarget.tv"].waitForExistence(timeout: 8))
        app.buttons["remoteTarget.tv"].tap(); sleep(2)
        app.buttons["Sesi artır"].firstMatch.tap(); sleep(1)
        app.buttons["remoteTarget.box"].tap(); sleep(2)
        app.swipeUp(); sleep(1)
        for d in ["1", "1", "9"] { app.buttons["boxDigit\(d)"].tap(); usleep(500_000) }
        sleep(2)
        app.swipeDown(); app.swipeDown(); sleep(1)
        // Web: open an address on the TV and mirror the page on the phone.
        app.buttons["Web tarayıcısı"].firstMatch.tap()
        let address = app.textFields["browserAddressInput"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        sleep(1)
        address.typeText("tr.wikipedia.org")
        sleep(1)
        app.buttons["TV'de aç"].tap()
        sleep(6)
        app.swipeUp(); sleep(2)
        app.swipeDown(); sleep(2)
        app.tabBars.buttons["Uygulamalar"].firstMatch.tap(); sleep(2)
        app.tabBars.buttons["Klavye"].firstMatch.tap(); sleep(2)
        app.tabBars.buttons["Cihazlar"].firstMatch.tap(); sleep(2)
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
