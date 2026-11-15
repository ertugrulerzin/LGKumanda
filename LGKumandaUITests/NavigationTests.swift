import XCTest

final class NavigationTests: XCTestCase {
    func testRenameHomeShortcutAndBrowserAddressEntry() {
        let app = XCUIApplication()
        app.launch()
        let netflix = app.buttons["shortcut.app:netflix"]
        XCTAssertTrue(netflix.waitForExistence(timeout:12))
        capture("Ana ekran kısayolları")
        let original = netflix.label
        app.navigationBars["Kumanda"].buttons["Kısayolları düzenle"].tap()
        app.buttons["editShortcut.app:netflix"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout:3))
        name.tap(); name.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:(name.value as? String ?? "").count))
        name.typeText("Film")
        app.alerts.buttons["Kaydet"].tap()
        capture("Kısayol düzenleme")
        app.buttons["editShortcut.app:netflix"].tap()
        let restore = app.alerts.textFields.firstMatch
        restore.tap(); restore.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:(restore.value as? String ?? "").count))
        restore.typeText(original)
        app.alerts.buttons["Kaydet"].tap()
        app.navigationBars["Kısayollar"].buttons["Bitti"].tap()
        app.tabBars.buttons["Klavye"].tap()
        app.buttons["Web adresi aç"].tap()
        let address = app.textFields["browserAddressInput"]
        XCTAssertTrue(address.waitForExistence(timeout:3))
        address.tap(); address.typeText("file:///test")
        app.buttons["TV'de aç"].tap()
        XCTAssertTrue(app.staticTexts["Geçerli bir web adresi veya arama gir. Örnek: example.com ya da hava durumu"].exists)
        address.tap(); address.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:(address.value as? String ?? "").count))
        address.typeText("example.com")
        XCTAssertTrue(app.buttons["TV'de aç"].isEnabled)
        XCTAssertFalse(app.staticTexts["Geçerli bir web adresi veya arama gir. Örnek: example.com ya da hava durumu"].exists)
        capture("iPhone ile web adresi")
        app.navigationBars["Web adresi"].buttons["Bitti"].tap()
        app.tabBars.buttons["Kumanda"].tap()
        app.buttons["Kontrol hedefi"].tap()
        app.buttons["HDMI kutusu yardımı"].tap()
        XCTAssertTrue(app.navigationBars["HDMI kutusu"].waitForExistence(timeout:3))
        capture("HDMI kutusu kontrolü")
        app.buttons["openBoxSetup"].tap()
        XCTAssertTrue(app.navigationBars["Wi-Fi ile kutu kumandası"].waitForExistence(timeout:3))
        XCTAssertTrue(app.staticTexts["Bulunan kutular"].exists || app.staticTexts["Kutunun bağlı olduğu giriş"].exists)
        capture("Wi-Fi ile kutu kumandası")
        app.navigationBars["Wi-Fi ile kutu kumandası"].buttons["Bitti"].tap()
        app.navigationBars["HDMI kutusu"].buttons["Bitti"].tap()
    }
    func testDiscoverTVOnLocalNetwork() throws {
        guard ProcessInfo.processInfo.environment["LG_LIVE_TV_TEST"] == "1" else {
            throw XCTSkip("Requires a powered-on LG TV on the local Wi-Fi.")
        }
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Cihazlar"].tap()
        app.buttons["Ağda LG TV ara"].tap()
        let discovered = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "LG webOS TV")).firstMatch
        XCTAssertTrue(discovered.waitForExistence(timeout: 30))
        capture("Ağda LG TV bulundu")
        if app.buttons["Aramayı durdur"].exists { app.buttons["Aramayı durdur"].tap() }
    }
    func testRemoteLibraryAndDeviceEditor() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Kumanda"].waitForExistence(timeout: 5))
        capture("Kumanda")
        app.tabBars.buttons["Uygulamalar"].tap()
        XCTAssertTrue(app.navigationBars["Uygulamalar"].exists)
        capture("Uygulamalar")
        app.tabBars.buttons["Kanallar"].tap()
        XCTAssertTrue(app.navigationBars["Kanallar"].exists)
        capture("Kanallar")
        app.tabBars.buttons["Cihazlar"].tap()
        XCTAssertTrue(app.buttons["Ağda LG TV ara"].exists)
        app.navigationBars["Cihazlar"].buttons["Televizyon ekle"].tap()
        XCTAssertTrue(app.navigationBars["Televizyon ekle"].waitForExistence(timeout: 3))
        let address = app.textFields["IP adresi · 192.168.1.50"]
        address.tap(); address.typeText("8.8.8.8")
        app.navigationBars["Televizyon ekle"].buttons["Bağlan"].tap()
        XCTAssertTrue(app.staticTexts["Geçerli bir yerel IPv4 adresi gir. Örnek: 192.168.1.50"].exists)
        app.buttons["İptal"].tap()
        app.tabBars.buttons["Kumanda"].tap()
    }
    func testKeyboardErgonomicsAndCursorlessMode() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Klavye"].tap()
        XCTAssertTrue(app.navigationBars["Klavye ve fare"].waitForExistence(timeout: 5))
        if app.staticTexts["HDMI kutusunda yön tuşlarını kullan. TV'nin metin klavyesi ve fare imleci kutuya aktarılmaz."].waitForExistence(timeout: 2) {
            XCTAssertFalse(app.buttons["Metni TV'ye gönder"].isEnabled)
            capture("HDMI işaretçisiz kontrol")
            app.tabBars.buttons["Kumanda"].tap()
            return
        }
        let field = app.textFields["tvTextInput"]
        XCTAssertTrue(field.exists)
        field.tap()
        field.typeText("Merhaba TV")
        capture("Klavye açık")
        app.buttons["iPhone klavyesini gizle"].tap()
        app.segmentedControls.buttons["İşaretçisiz"].tap()
        XCTAssertTrue(app.staticTexts["İmleci oynatmadan gezin"].exists)
        capture("İşaretçisiz gezinme")
        app.segmentedControls.buttons["Fare"].tap()
        XCTAssertTrue(app.sliders["Fare hassasiyeti"].exists)
        capture("Fare modu")
        app.segmentedControls.buttons["İşaretçisiz"].tap()
        app.tabBars.buttons["Kumanda"].tap()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
