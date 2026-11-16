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
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
