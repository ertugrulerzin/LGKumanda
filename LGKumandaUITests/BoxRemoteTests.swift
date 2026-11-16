import XCTest

final class BoxRemoteTests: XCTestCase {
    /// A paired box shows the TV | Tivibu switch; the Tivibu remote keeps the number pad visible.
    func testTivibuRemoteLayout() {
        let app = XCUIApplication()
        // Seed a paired box (TEST-NET address, never reachable) through the defaults argument domain.
        app.launchArguments += ["-androidTVBox", "<7b22686f7374223a20223139322e302e322e3130222c20226e616d65223a2022546976696275222c2022696e7075744944223a202248444d495f33222c2022706169726564223a20747275657d>"]
        app.launch()
        let target = app.segmentedControls["remoteTarget"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["boxSettings"].waitForExistence(timeout: 3) || app.staticTexts["boxStatus"].exists)
        app.swipeUp()
        XCTAssertTrue(app.buttons["boxDigit1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["boxDigit0"].exists)
        XCTAssertTrue(app.buttons["boxPlayPause"].exists)
        app.buttons["boxDigit1"].tap()
        XCTAssertTrue(app.staticTexts["boxTypedChannel"].label.contains("1"))
        app.swipeDown()
        target.buttons.element(boundBy: 0).tap()
        XCTAssertFalse(app.buttons["boxDigit1"].exists)
    }
}
