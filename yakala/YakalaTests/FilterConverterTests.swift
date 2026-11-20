import WebKit
import XCTest

final class FilterConverterTests: XCTestCase {
    func testHostRule() throws {
        let n = try XCTUnwrap(FilterConverter.network("||ads.example.com^$third-party,script,domain=a.com|~b.a.com"))
        XCTAssertEqual(n.trigger.urlFilter, "^[^:]+://+([^:/]+\\.)?ads\\.example\\.com[/:?=&]")
        XCTAssertEqual(n.trigger.loadType, ["third-party"])
        XCTAssertEqual(n.trigger.resourceType, ["script"])
        XCTAssertEqual(n.trigger.ifDomain, ["*a.com"], "mixed include/exclude keeps includes")
    }

    func testPatternsAndOptions() {
        XCTAssertEqual(FilterConverter.regex(from: "/banner/*/ad.gif|"), "/banner/.*/ad\\.gif$")
        XCTAssertEqual(FilterConverter.regex(from: "|https://x.com/?a="), "^https://x\\.com/\\?a=")
        XCTAssertNil(FilterConverter.regex(from: "/ad{2}"))
        XCTAssertNil(FilterConverter.network("/^https?:\\/\\/ad/"), "regex rules skipped")
        XCTAssertNil(FilterConverter.network("||x.com^$csp=script-src 'none'"), "unsupported option skipped")
        XCTAssertNil(FilterConverter.network("$third-party"), "would block everything")
        let neg = FilterConverter.network("||cdn.com/ads/$~image")
        XCTAssertEqual(neg?.trigger.resourceType?.contains("image"), false)
        XCTAssertEqual(neg?.trigger.resourceType?.contains("script"), true)
    }

    func testRuleOrderAndCosmetics() {
        let rules = FilterConverter.convert("""
        [Adblock Plus 2.0]
        ! comment
        ||tracker.net^
        @@||tracker.net/ok.js
        ##.ad-banner
        ##.keep-me
        #@#.keep-me
        example.com,news.example.com##.sidebar-ad
        @@||trusted.org^$document
        example.com#?#div:has(> .ad)
        example.com#$#.x { display: none }
        """)
        let types = rules.map(\.action.type)
        XCTAssertEqual(types, ["block", "css-display-none", "css-display-none", "ignore-previous-rules", "ignore-previous-rules"])
        XCTAssertEqual(rules[1].action.selector, ".ad-banner")
        XCTAssertEqual(rules[2].trigger.ifDomain, ["*example.com", "*news.example.com"])
        XCTAssertEqual(rules[4].trigger.ifDomain, ["*trusted.org"])
        XCTAssertEqual(rules[4].trigger.urlFilter, ".*")
    }

    /// Downloads the real EasyList and compiles it with WebKit. Skipped offline.
    @MainActor
    func testRealEasyListCompiles() async throws {
        let url = URL(string: "https://easylist.to/easylist/easylist.txt")!
        guard let text = try? await HTTP.text(URLRequest(url: url, timeoutInterval: 30)) else {
            throw XCTSkip("EasyList indirilemedi")
        }
        let rules = FilterConverter.convert(text)
        XCTAssertGreaterThan(rules.count, 20_000)
        let store = try XCTUnwrap(WKContentRuleListStore.default())
        let start = Date()
        do {
            let list = try await store.compileContentRuleList(forIdentifier: "yakala.test", encodedContentRuleList: FilterConverter.json(rules))
            XCTAssertNotNil(list)
        } catch {
            XCTFail("EasyList derlenemedi: \(error)")
        }
        print("EasyList: \(rules.count) kural, derleme \(String(format: "%.1f", -start.timeIntervalSinceNow)) sn")
        try? await store.removeContentRuleList(forIdentifier: "yakala.test")
    }
}
