import XCTest
@testable import GanderCore

final class ContentBlockerTests: XCTestCase {
    func testDomainFilterShape() {
        XCTAssertEqual(
            ContentBlocker.urlFilter(forDomain: "Ads.Example.com"),
            "^[^:]+://+([^:/]+\\.)?ads\\.example\\.com[:/]"
        )
    }

    /// The filter is a regular expression, so check it behaves like one.
    func testDomainFilterMatchesTheDomainAndItsSubdomainsOnly() throws {
        let regex = try NSRegularExpression(pattern: ContentBlocker.urlFilter(forDomain: "example.com"))
        func matches(_ url: String) -> Bool {
            regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
        }
        XCTAssertTrue(matches("https://example.com/ad.js"))
        XCTAssertTrue(matches("https://cdn.example.com/ad.js"))
        XCTAssertTrue(matches("http://a.b.example.com:8080/x"))
        XCTAssertFalse(matches("https://notexample.com/ad.js"))
        XCTAssertFalse(matches("https://example.com.evil.net/ad.js"))
        XCTAssertFalse(matches("https://site.net/?u=https://example.com/"))
        XCTAssertFalse(matches("https://exampleXcom/"))
    }

    func testBuiltInRulesFollowOptions() {
        let none = ContentBlocker.builtInRules(for: .init(blockAds: false, blockTrackers: false, hideCookieBanners: false))
        XCTAssertTrue(none.isEmpty)

        let adsOnly = ContentBlocker.builtInRules(for: .init(blockAds: true, blockTrackers: false, hideCookieBanners: false))
        XCTAssertTrue(adsOnly.contains { $0.trigger.urlFilter.contains("doubleclick\\.net") })
        XCTAssertFalse(adsOnly.contains { $0.trigger.urlFilter.contains("google-analytics") })

        let bannersOnly = ContentBlocker.builtInRules(for: .init(blockAds: false, blockTrackers: false, hideCookieBanners: true))
        XCTAssertFalse(bannersOnly.isEmpty)
        XCTAssertTrue(bannersOnly.allSatisfy { $0.action.type == "css-display-none" })
        XCTAssertTrue(bannersOnly.contains { $0.action.selector?.contains("#onetrust-consent-sdk") == true })
    }

    /// First-party requests must never be blocked, or opening an analytics
    /// dashboard as a tile would break.
    func testEveryNetworkRuleIsThirdPartyOnly() {
        let rules = ContentBlocker.builtInRules(for: .init())
        let blocking = rules.filter { $0.action.type == "block" }
        XCTAssertGreaterThan(blocking.count, 100)
        XCTAssertTrue(blocking.allSatisfy { $0.trigger.loadType == ["third-party"] })
    }

    func testBuiltInListsAreWellFormed() {
        let domains = BlockLists.adDomains + BlockLists.trackerDomains
        for domain in domains {
            XCTAssertTrue(FilterListParser.isDomain(domain), "not a domain: \(domain)")
            XCTAssertEqual(domain, domain.lowercased())
        }
        XCTAssertEqual(Set(domains).count, domains.count, "duplicate domains: \(duplicates(in: domains))")

        let selectors = BlockLists.cookieBannerSelectors + BlockLists.adSelectors
        for selector in selectors {
            XCTAssertTrue(ElementHiding.isValidSelector(selector), "bad selector: \(selector)")
            XCTAssertFalse(selector.contains(","), "one selector per entry: \(selector)")
        }
        XCTAssertEqual(Set(selectors).count, selectors.count, "duplicate selectors: \(duplicates(in: selectors))")
    }

    /// WebKit refuses a whole rule list if any of it is not plain ASCII.
    func testEncodedRulesAreASCIIJSONInWebKitShape() throws {
        let json = try XCTUnwrap(ContentBlocker.encode(ContentBlocker.builtInRules(for: .init())))
        XCTAssertTrue(json.unicodeScalars.allSatisfy(\.isASCII))

        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        let first = try XCTUnwrap(parsed.first)
        let trigger = try XCTUnwrap(first["trigger"] as? [String: Any])
        let action = try XCTUnwrap(first["action"] as? [String: Any])
        XCTAssertNotNil(trigger["url-filter"] as? String)
        XCTAssertEqual(trigger["load-type"] as? [String], ["third-party"])
        XCTAssertEqual(action["type"] as? String, "block")
        XCTAssertNil(action["selector"], "absent values must be omitted, not null")
    }

    func testEmptyRuleSetEncodesToNothing() {
        XCTAssertNil(ContentBlocker.encode([]))
    }

    func testIdentifierTracksContent() {
        let a = ContentBlocker.identifier(prefix: "gander", json: "[1]")
        XCTAssertEqual(a, ContentBlocker.identifier(prefix: "gander", json: "[1]"))
        XCTAssertNotEqual(a, ContentBlocker.identifier(prefix: "gander", json: "[2]"))
        XCTAssertTrue(a.hasPrefix("gander-"))
    }

    private func duplicates(in values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !seen.insert($0).inserted }
    }
}

final class FilterListParserTests: XCTestCase {
    func testCommentsAndHeadersAreIgnored() {
        let result = FilterListParser.parse("""
        [Adblock Plus 2.0]
        ! Title: test

        # hosts-style comment
        """)
        XCTAssertEqual(result, FilterListParser.Result(rules: [], skipped: 0))
    }

    func testDomainAnchoredRule() {
        let rule = FilterListParser.parseLine("||ads.example.com^")
        XCTAssertEqual(rule?.trigger.urlFilter, ContentBlocker.urlFilter(forDomain: "ads.example.com"))
        XCTAssertEqual(rule?.action, .block)
        XCTAssertNil(rule?.trigger.loadType)
    }

    func testOptions() {
        let rule = FilterListParser.parseLine("||tracker.io^$third-party,script,domain=a.com|b.org")
        XCTAssertEqual(rule?.trigger.loadType, ["third-party"])
        XCTAssertEqual(rule?.trigger.resourceType, ["script"])
        XCTAssertEqual(rule?.trigger.ifDomain, ["*a.com", "*b.org"])

        XCTAssertEqual(FilterListParser.parseLine("||x.com^$domain=~a.com")?.trigger.unlessDomain, ["*a.com"])
        XCTAssertNil(FilterListParser.parseLine("||x.com^$domain=a.com|~b.com"), "WebKit cannot mix include and exclude")
        XCTAssertNil(FilterListParser.parseLine("||x.com^$redirect=noop.js"), "unknown options skip the rule")
    }

    func testPathPattern() throws {
        let rule = try XCTUnwrap(FilterListParser.parseLine("||example.com/ads/*.js"))
        XCTAssertEqual(rule.trigger.urlFilter, "^[^:]+://+([^:/]+\\.)?example\\.com/ads/.*\\.js")
        let regex = try NSRegularExpression(pattern: rule.trigger.urlFilter)
        let url = "https://static.example.com/ads/banner.js"
        XCTAssertNotNil(regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)))
    }

    func testAnchorsAndSeparator() {
        XCTAssertEqual(FilterListParser.parseLine("|https://example.com/x|")?.trigger.urlFilter, "^https://example\\.com/x$")
        XCTAssertEqual(FilterListParser.parseLine("/banner^ad")?.trigger.urlFilter, "/banner[^a-zA-Z0-9_.%-]ad")
    }

    func testHostsFileLines() {
        XCTAssertEqual(
            FilterListParser.parseLine("0.0.0.0 ads.example.com"),
            ContentBlocker.blockThirdParty(domain: "ads.example.com")
        )
        XCTAssertNil(FilterListParser.parseLine("0.0.0.0 not a domain"))
    }

    func testCosmeticRules() {
        let global = FilterListParser.parseLine("##.ad-banner")
        XCTAssertEqual(global?.action, .hide(".ad-banner"))
        XCTAssertEqual(global?.trigger.urlFilter, ".*")
        XCTAssertNil(global?.trigger.ifDomain)

        let scoped = FilterListParser.parseLine("example.com,news.org##div > .promo")
        XCTAssertEqual(scoped?.trigger.ifDomain, ["*example.com", "*news.org"])
        XCTAssertEqual(scoped?.action.selector, "div > .promo")

        XCTAssertEqual(FilterListParser.parseLine("~example.com##.x")?.trigger.unlessDomain, ["*example.com"])
    }

    func testUnsupportedSyntaxIsSkippedNotGuessed() {
        let unsupported = [
            "@@||example.com^",
            "/ads[0-9]+/",
            "example.com#@#.ad",
            "example.com#?#div:-abp-has(.ad)",
            "example.com##div:has-text(Sponsored)",
            "example.com##.x { color: red }",
            "||exämple.com^",
            "ab",
            "a.com,~b.com##.x",
        ]
        for line in unsupported {
            XCTAssertNil(FilterListParser.parseLine(line), line)
        }
        let result = FilterListParser.parse(unsupported.joined(separator: "\n") + "\n||good.com^")
        XCTAssertEqual(result.rules.count, 1)
        XCTAssertEqual(result.skipped, unsupported.count)
    }

    func testParsedRulesEncode() {
        let result = FilterListParser.parse("||a.com^\nb.com##.x\n")
        XCTAssertNotNil(ContentBlocker.encode(result.rules))
    }
}

final class ElementHidingTests: XCTestCase {
    func testSelectorValidation() {
        XCTAssertTrue(ElementHiding.isValidSelector("div.sidebar > ul:nth-of-type(2)"))
        XCTAssertTrue(ElementHiding.isValidSelector("[data-x=\"y\"]"))
        XCTAssertFalse(ElementHiding.isValidSelector(""))
        XCTAssertFalse(ElementHiding.isValidSelector("   "))
        XCTAssertFalse(ElementHiding.isValidSelector("a { } body { display:none"))
        XCTAssertFalse(ElementHiding.isValidSelector("a }"))
        XCTAssertFalse(ElementHiding.isValidSelector("</style><script>"))
        XCTAssertFalse(ElementHiding.isValidSelector("a\nb"))
    }

    func testSelectorsAreGroupedByNormalizedHost() {
        let grouped = ElementHiding.selectorsByHost([
            HiddenElement(host: "www.Example.com", selector: ".a"),
            HiddenElement(host: "example.com", selector: ".b"),
            HiddenElement(host: "example.com", selector: ".a"),
            HiddenElement(host: "other.org", selector: "#x"),
            HiddenElement(host: "other.org", selector: "bad { }"),
            HiddenElement(host: "", selector: ".c"),
        ])
        XCTAssertEqual(grouped, ["example.com": [".a", ".b"], "other.org": ["#x"]])
    }

    func testUserScriptEmbedsRulesAsJSON() throws {
        let script = ElementHiding.userScript(for: [
            HiddenElement(host: "example.com", selector: "div[title=\"it's \\\"quoted\\\"\"]"),
        ])
        // Pull the object literal back out and make sure it is intact JSON.
        let start = try XCTUnwrap(script.range(of: "var rules = "))
        let end = try XCTUnwrap(script.range(of: ";\n", range: start.upperBound..<script.endIndex))
        let json = String(script[start.upperBound..<end.lowerBound])
        let decoded = try JSONDecoder().decode([String: [String]].self, from: Data(json.utf8))
        XCTAssertEqual(decoded, ["example.com": ["div[title=\"it's \\\"quoted\\\"\"]"]])
    }

    func testUserScriptWithNothingHiddenStillCleansUp() {
        let script = ElementHiding.userScript(for: [])
        XCTAssertTrue(script.contains("var rules = {};"))
        XCTAssertTrue(script.contains("style.remove()"))
    }

    func testPickerScriptTalksToTheNamedHandler() {
        XCTAssertTrue(ElementHiding.pickerScript.contains("messageHandlers.\(ElementHiding.messageHandlerName)"))
    }
}
