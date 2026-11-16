import XCTest

final class BoxRemoteTests: XCTestCase {
    /// A paired box gets its own tab next to TV; the box remote keeps the number pad visible.
    func testTivibuRemoteLayout() {
        let app = XCUIApplication()
        // Seed a paired box (TEST-NET address, never reachable) through the defaults argument domain.
        app.launchArguments += ["-androidTVBox", "<7b22686f7374223a20223139322e302e322e3130222c20226e616d65223a2022546976696275222c2022696e7075744944223a202248444d495f33222c2022706169726564223a20747275657d>"]
        app.launch()
        let boxTab = app.buttons["remoteTarget.box"]
        XCTAssertTrue(boxTab.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["remoteTarget.add"].exists)
        boxTab.tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "box-tab"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(app.buttons["boxSettings"].waitForExistence(timeout: 3) || app.staticTexts["boxStatus"].exists)
        app.swipeUp()
        XCTAssertTrue(app.buttons["boxDigit1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["boxDigit0"].exists)
        XCTAssertTrue(app.buttons["boxPlayPause"].exists)
        app.buttons["boxDigit1"].tap()
        XCTAssertTrue(app.staticTexts["boxTypedChannel"].label.contains("1"))
        app.swipeDown()
        app.buttons["remoteTarget.tv"].tap()
        XCTAssertFalse(app.buttons["boxDigit1"].exists)
    }
}
