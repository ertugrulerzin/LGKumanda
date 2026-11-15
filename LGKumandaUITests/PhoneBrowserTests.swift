import XCTest

final class PhoneBrowserTests: XCTestCase {
    func testTappingLinkOnPhoneSendsItToTV() {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_PHONE_BROWSER"] = "https://example.com"
        app.launch()
        XCTAssertTrue(app.staticTexts["Dokunduğun bağlantı TV'de açılır. TV doğrulama isterse imleç düğmesine dokun."].waitForExistence(timeout: 5))
        let link = app.webViews.links.firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 20), "example.com should load on the phone")
        link.tap()
        // No TV is connected in UI tests, so forwarding the tapped page to the TV must surface the TV error.
        let forwarded = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'tarayıcısı bulunamadı'")).firstMatch
        XCTAssertTrue(forwarded.waitForExistence(timeout: 25), "Link tap must be forwarded to the TV")
        let back = app.buttons["Telefonda geri"]
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: back)
        waitForExpectations(timeout: 10)
    }

    func testPlayingVideoOnPhoneOpensTVTouchPad() {
        let app = XCUIApplication()
        let html = "<meta name=viewport content='width=device-width'><video id=v playsinline></video><button style='font-size:40px' onclick=\"document.getElementById('v').play()\">Oynat</button>"
        app.launchEnvironment["UITEST_PHONE_BROWSER"] = "data:text/html," + html.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        app.launch()
        let play = app.webViews.buttons["Oynat"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        XCTAssertTrue(app.navigationBars["TV'de dokunmatik"].waitForExistence(timeout: 5), "Play on the phone must open the TV touch pad")
        XCTAssertTrue(app.descendants(matching: .any)["playOnTVHint"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["tvClick"].exists, "TV pad offers a click button")
        XCTAssertTrue(app.buttons["İşaretçiyi sağ kaydır"].exists, "TV pad offers fine pointer nudges")
    }
}
