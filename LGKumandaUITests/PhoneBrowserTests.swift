import XCTest

final class PhoneBrowserTests: XCTestCase {
    private func browser(_ html: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_PHONE_BROWSER"] = "data:text/html;charset=utf-8," + html.addingPercentEncoding(withAllowedCharacters:.alphanumerics)!
        app.launch()
        return app
    }
    func testFirstSelectedLinkIsForwardedToTV() {
        let app = browser("<meta name=viewport content='width=device-width'><a style='font-size:32px' href='https://example.com/selected'>Seçilen sayfa</a>")
        let link = app.webViews.links["Seçilen sayfa"]
        XCTAssertTrue(link.waitForExistence(timeout:10))
        link.tap()
        let forwarded = app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'tarayıcısı bulunamadı'")).firstMatch
        XCTAssertTrue(forwarded.waitForExistence(timeout:8),"The first chosen link is sent immediately, independently of page loading")
    }
    func testVideoSourcesAndPhoneOnlyFallbackAreReachable() {
        let app = browser("""
        <meta name=viewport content='width=device-width'><title>Örnek video</title>
        <video id=v preload=none playsinline><source src='https://example.com/movie.mp4' type='video/mp4'></video>
        <button style='font-size:36px' onclick="document.getElementById('v').dispatchEvent(new Event('play'))">Videoyu seç</button>
        """)
        let play = app.webViews.buttons["Videoyu seç"]
        XCTAssertTrue(play.waitForExistence(timeout:10)); play.tap()
        XCTAssertTrue(app.navigationBars["Web videoları"].waitForExistence(timeout:5))
        let source = app.buttons["openWebVideo.0"]
        XCTAssertTrue(source.waitForExistence(timeout:5))
        XCTAssertFalse(source.isEnabled,"No connected TV in this fixture")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'MP4' AND label CONTAINS 'example.com'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["TV'de oynat"].exists)
        XCTAssertTrue(app.buttons["TV'de duraklat"].exists)
        app.swipeUp()
        XCTAssertTrue(app.buttons["webVideoPointer"].waitForExistence(timeout:3))
    }
    func testEmptyVideoCatalogExplainsRecovery() {
        let app = browser("<meta name=viewport content='width=device-width'><h1>Bir web sayfası</h1>")
        let videos = app.buttons["webVideos"]
        XCTAssertTrue(videos.waitForExistence(timeout:8)); videos.tap()
        XCTAssertTrue(app.staticTexts["Henüz video bağlantısı bulunmadı"].waitForExistence(timeout:3))
        app.swipeUp()
        XCTAssertTrue(app.buttons["webVideoPointer"].waitForExistence(timeout:3))
    }
}
