import Foundation

/// One entry of a WebKit content rule list.
/// https://developer.apple.com/documentation/safariservices/creating-a-content-blocker
public struct ContentRule: Codable, Hashable, Sendable {
    public struct Trigger: Codable, Hashable, Sendable {
        public var urlFilter: String
        public var loadType: [String]?
        public var resourceType: [String]?
        public var ifDomain: [String]?
        public var unlessDomain: [String]?

        public init(
            urlFilter: String,
            loadType: [String]? = nil,
            resourceType: [String]? = nil,
            ifDomain: [String]? = nil,
            unlessDomain: [String]? = nil
        ) {
            self.urlFilter = urlFilter
            self.loadType = loadType
            self.resourceType = resourceType
            self.ifDomain = ifDomain
            self.unlessDomain = unlessDomain
        }

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case loadType = "load-type"
            case resourceType = "resource-type"
            case ifDomain = "if-domain"
            case unlessDomain = "unless-domain"
        }
    }

    public struct Action: Codable, Hashable, Sendable {
        public var type: String
        public var selector: String?

        public static let block = Action(type: "block", selector: nil)

        public static func hide(_ selector: String) -> Action {
            Action(type: "css-display-none", selector: selector)
        }
    }

    public var trigger: Trigger
    public var action: Action

    public init(trigger: Trigger, action: Action) {
        self.trigger = trigger
        self.action = action
    }
}

public enum ContentBlocker {
    public struct Options: Hashable, Sendable {
        public var blockAds: Bool
        public var blockTrackers: Bool
        public var hideCookieBanners: Bool

        public init(blockAds: Bool = true, blockTrackers: Bool = true, hideCookieBanners: Bool = true) {
            self.blockAds = blockAds
            self.blockTrackers = blockTrackers
            self.hideCookieBanners = hideCookieBanners
        }
    }

    /// Rules from the lists that ship with the app.
    ///
    /// Network rules only ever block third-party requests, so opening an
    /// analytics dashboard as a tile still works while the same company's
    /// tracker is blocked everywhere else.
    public static func builtInRules(for options: Options) -> [ContentRule] {
        var rules: [ContentRule] = []
        if options.blockAds {
            rules += BlockLists.adDomains.map(blockThirdParty)
            rules += hide(BlockLists.adSelectors)
        }
        if options.blockTrackers {
            rules += BlockLists.trackerDomains.map(blockThirdParty)
        }
        if options.hideCookieBanners {
            rules += hide(BlockLists.cookieBannerSelectors)
        }
        return rules
    }

    public static func blockThirdParty(domain: String) -> ContentRule {
        ContentRule(
            trigger: ContentRule.Trigger(urlFilter: urlFilter(forDomain: domain), loadType: ["third-party"]),
            action: .block
        )
    }

    /// A WebKit-flavoured regex matching `domain` and all of its subdomains.
    public static func urlFilter(forDomain domain: String) -> String {
        "^[^:]+://+([^:/]+\\.)?" + escapeRegex(domain.lowercased()) + "[:/]"
    }

    public static func escapeRegex(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\.+*?^$()[]{}|".contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    /// The JSON WebKit compiles, or nil when there is nothing to compile
    /// (WebKit rejects an empty list).
    public static func encode(_ rules: [ContentRule]) -> String? {
        guard !rules.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(rules) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// A name for a compiled list that changes whenever its contents do, so a
    /// cached compilation is reused only while it is still current.
    public static func identifier(prefix: String, json: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in json.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return prefix + "-" + String(hash, radix: 16)
    }

    private static func hide(_ selectors: [String], chunk: Int = 24) -> [ContentRule] {
        stride(from: 0, to: selectors.count, by: chunk).map { start in
            let group = selectors[start..<min(start + chunk, selectors.count)]
            return ContentRule(
                trigger: ContentRule.Trigger(urlFilter: ".*"),
                action: .hide(group.joined(separator: ", "))
            )
        }
    }
}

/// Reads the common subset of Adblock Plus / EasyList filter syntax.
///
/// Anything that cannot be expressed faithfully as a WebKit content rule is
/// skipped rather than approximated, because a wrong rule breaks pages.
public enum FilterListParser {
    public struct Result: Hashable, Sendable {
        public var rules: [ContentRule]
        /// Lines that looked like filters but are not supported.
        public var skipped: Int
    }

    public static func parse(_ text: String) -> Result {
        var rules: [ContentRule] = []
        var skipped = 0
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") || line.hasPrefix("# ") || line == "#" {
                continue
            }
            if let rule = parseLine(line) {
                rules.append(rule)
            } else {
                skipped += 1
            }
        }
        return Result(rules: rules, skipped: skipped)
    }

    static func parseLine(_ line: String) -> ContentRule? {
        guard line.unicodeScalars.allSatisfy({ $0.isASCII && $0.value >= 0x20 && $0.value != 0x7f }) else { return nil }
        if line.hasPrefix("@@") { return nil }

        for marker in ["#@#", "#?#", "#$#", "#%#"] where line.contains(marker) {
            return nil
        }
        if let range = line.range(of: "##") {
            return cosmeticRule(domains: String(line[..<range.lowerBound]), selector: String(line[range.upperBound...]))
        }

        // Hosts-file format: "0.0.0.0 ads.example.com".
        let words = line.split(separator: " ", omittingEmptySubsequences: true)
        if words.count == 2, words[0] == "0.0.0.0" || words[0] == "127.0.0.1", isDomain(String(words[1])) {
            return ContentBlocker.blockThirdParty(domain: String(words[1]))
        }
        guard words.count == 1 else { return nil }
        return networkRule(line)
    }

    // MARK: - Cosmetic filters

    private static func cosmeticRule(domains: String, selector: String) -> ContentRule? {
        let selector = selector.trimmingCharacters(in: .whitespaces)
        guard ElementHiding.isValidSelector(selector) else { return nil }
        for extended in [":-abp-", ":has-text(", ":contains(", ":xpath(", ":matches-css", ":upward(", ":remove(", ":style(", ":min-text-length(", ":watch-attr("] where selector.contains(extended) {
            return nil
        }

        var trigger = ContentRule.Trigger(urlFilter: ".*")
        if !domains.isEmpty {
            let list = domains.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            let excluded = list.filter { $0.hasPrefix("~") }.map { String($0.dropFirst()) }
            let included = list.filter { !$0.hasPrefix("~") }
            // WebKit allows either list on a rule, never both.
            guard excluded.isEmpty || included.isEmpty else { return nil }
            guard (included + excluded).allSatisfy(isDomain) else { return nil }
            if !included.isEmpty { trigger.ifDomain = included.map { "*" + $0 } }
            if !excluded.isEmpty { trigger.unlessDomain = excluded.map { "*" + $0 } }
        }
        return ContentRule(trigger: trigger, action: .hide(selector))
    }

    // MARK: - Network filters

    private static func networkRule(_ line: String) -> ContentRule? {
        var pattern = line
        var trigger = ContentRule.Trigger(urlFilter: "")

        if let dollar = pattern.lastIndex(of: "$"), dollar != pattern.startIndex {
            let options = String(pattern[pattern.index(after: dollar)...])
            guard applyOptions(options, to: &trigger) else { return nil }
            pattern = String(pattern[..<dollar])
        }
        // Regular-expression filters use syntax WebKit does not accept.
        if pattern.hasPrefix("/"), pattern.hasSuffix("/"), pattern.count > 1 { return nil }
        guard !pattern.isEmpty, pattern != "*" else { return nil }

        var regex = ""
        if pattern.hasPrefix("||") {
            pattern.removeFirst(2)
            let domain = pattern.hasSuffix("^") ? String(pattern.dropLast()) : pattern
            if isDomain(domain) {
                trigger.urlFilter = ContentBlocker.urlFilter(forDomain: domain)
                return ContentRule(trigger: trigger, action: .block)
            }
            regex = "^[^:]+://+([^:/]+\\.)?"
        } else if pattern.hasPrefix("|") {
            pattern.removeFirst()
            regex = "^"
        }

        var anchoredEnd = false
        if pattern.hasSuffix("|") {
            pattern.removeLast()
            anchoredEnd = true
        }
        guard pattern.count >= 3, !pattern.contains("|") else { return nil }

        for character in pattern {
            switch character {
            case "*": regex += ".*"
            case "^": regex += "[^a-zA-Z0-9_.%-]"
            default: regex += ContentBlocker.escapeRegex(String(character))
            }
        }
        if anchoredEnd { regex += "$" }
        trigger.urlFilter = regex
        return ContentRule(trigger: trigger, action: .block)
    }

    private static func applyOptions(_ options: String, to trigger: inout ContentRule.Trigger) -> Bool {
        var resourceTypes: [String] = []
        for option in options.split(separator: ",").map({ $0.lowercased() }) {
            switch option {
            case "third-party", "3p": trigger.loadType = ["third-party"]
            case "~third-party", "first-party", "1p": trigger.loadType = ["first-party"]
            case "script": resourceTypes.append("script")
            case "image": resourceTypes.append("image")
            case "stylesheet", "css": resourceTypes.append("style-sheet")
            case "font": resourceTypes.append("font")
            case "media": resourceTypes.append("media")
            case "xmlhttprequest", "xhr": resourceTypes.append("raw")
            case "subdocument", "frame", "document", "doc": resourceTypes.append("document")
            case "popup": resourceTypes.append("popup")
            case "important": break
            default:
                guard option.hasPrefix("domain=") else { return false }
                let list = option.dropFirst("domain=".count).split(separator: "|").map(String.init)
                let excluded = list.filter { $0.hasPrefix("~") }.map { String($0.dropFirst()) }
                let included = list.filter { !$0.hasPrefix("~") }
                guard !list.isEmpty, excluded.isEmpty || included.isEmpty,
                      (included + excluded).allSatisfy(isDomain) else { return false }
                if !included.isEmpty { trigger.ifDomain = included.map { "*" + $0 } }
                if !excluded.isEmpty { trigger.unlessDomain = excluded.map { "*" + $0 } }
            }
        }
        if !resourceTypes.isEmpty { trigger.resourceType = resourceTypes }
        return true
    }

    static func isDomain(_ text: String) -> Bool {
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, text.count <= 253 else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}
