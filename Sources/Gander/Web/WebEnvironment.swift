import AppKit
import GanderCore
import WebKit

/// State shared by every web tile: the compiled content-blocking rules.
@MainActor
final class WebEnvironment {
    /// Compiled rule lists currently in force.
    private(set) var ruleLists: [WKContentRuleList] = []
    /// False until the first compilation has finished. Web tiles hold their
    /// first load until then, so it is already filtered.
    private(set) var isReady = false
    /// Why the user's own filters could not be used, if they could not.
    private(set) var customFilterError: String?
    /// Called whenever `ruleLists` changes.
    var onChange: (() -> Void)?

    private var appliedKey: String?
    private var generation = 0

    private struct Request {
        var isCustom: Bool
        var identifier: String
        var json: String
    }

    func configure(for settings: AppSettings) {
        let builtIn = ContentBlocker.encode(ContentBlocker.builtInRules(for: settings.contentBlocking))
        let custom = ContentBlocker.encode(FilterListParser.parse(settings.customFilters).rules)
        let key = (builtIn ?? "") + "\u{0}" + (custom ?? "")
        guard key != appliedKey else { return }
        appliedKey = key

        // The two lists are compiled separately so that a mistake in the
        // user's filters cannot take the built-in blocking down with it.
        var requests: [Request] = []
        if let builtIn {
            let identifier = ContentBlocker.identifier(prefix: "gander-builtin", json: builtIn)
            requests.append(Request(isCustom: false, identifier: identifier, json: builtIn))
        }
        if let custom {
            let identifier = ContentBlocker.identifier(prefix: "gander-custom", json: custom)
            requests.append(Request(isCustom: true, identifier: identifier, json: custom))
        }

        generation += 1
        compileNext(requests, index: 0, compiled: [], customError: nil, generation: generation)
    }

    private func compileNext(
        _ requests: [Request],
        index: Int,
        compiled: [WKContentRuleList],
        customError: String?,
        generation: Int
    ) {
        // Settings changed again while this was compiling; a newer run wins.
        guard generation == self.generation else { return }
        guard index < requests.count else {
            ruleLists = compiled
            customFilterError = customError
            isReady = true
            onChange?()
            removeStaleLists(keeping: requests.map(\.identifier))
            return
        }

        let request = requests[index]
        compile(identifier: request.identifier, json: request.json) { [weak self] list, error in
            var compiled = compiled
            var customError = customError
            if let list {
                compiled.append(list)
            } else if request.isCustom {
                customError = error ?? "The filters could not be compiled."
            } else {
                NSLog("Gander: built-in content rules failed to compile: \(error ?? "unknown error")")
            }
            self?.compileNext(
                requests, index: index + 1, compiled: compiled, customError: customError, generation: generation
            )
        }
    }

    private func compile(
        identifier: String,
        json: String,
        completion: @escaping @MainActor (WKContentRuleList?, String?) -> Void
    ) {
        guard let store = WKContentRuleListStore.default() else {
            completion(nil, "Content blocking is unavailable.")
            return
        }
        store.lookUpContentRuleList(forIdentifier: identifier) { cached, _ in
            if let cached {
                onMainActor { completion(cached, nil) }
                return
            }
            store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
                let message = error?.localizedDescription
                onMainActor { completion(list, message) }
            }
        }
    }

    /// Compiled lists are cached on disk under their identifier; drop the
    /// ones that belong to settings no longer in use.
    private func removeStaleLists(keeping current: [String]) {
        guard let store = WKContentRuleListStore.default() else { return }
        store.getAvailableContentRuleListIdentifiers { identifiers in
            for identifier in identifiers ?? [] where identifier.hasPrefix("gander-") && !current.contains(identifier) {
                store.removeContentRuleList(forIdentifier: identifier) { _ in }
            }
        }
    }

    // MARK: - Browsing data

    enum BrowsingData {
        case cache
        case cookiesAndSiteData

        var types: Set<String> {
            switch self {
            case .cache:
                return [
                    WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache,
                    WKWebsiteDataTypeFetchCache, WKWebsiteDataTypeOfflineWebApplicationCache,
                ]
            case .cookiesAndSiteData:
                return [
                    WKWebsiteDataTypeCookies, WKWebsiteDataTypeLocalStorage,
                    WKWebsiteDataTypeSessionStorage, WKWebsiteDataTypeIndexedDBDatabases,
                    WKWebsiteDataTypeWebSQLDatabases, WKWebsiteDataTypeServiceWorkerRegistrations,
                ]
            }
        }
    }

    func clear(_ data: BrowsingData, completion: @escaping @MainActor () -> Void) {
        WKWebsiteDataStore.default().removeData(ofTypes: data.types, modifiedSince: .distantPast) {
            onMainActor { completion() }
        }
    }

    // MARK: - User agent

    /// WKWebView's default user agent omits the "Version/… Safari/…" part, and
    /// some sites then refuse to load or serve a degraded page.
    static let desktopUserAgentSuffix: String = {
        let system = ProcessInfo.processInfo.operatingSystemVersion
        // Safari 17 shipped with macOS 14 and 18 with macOS 15; from macOS 26
        // on, the two share a version number.
        let safari = system.majorVersion >= 26 ? system.majorVersion : system.majorVersion + 3
        return "Version/\(safari).0 Safari/605.1.15"
    }()

    static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"
}
