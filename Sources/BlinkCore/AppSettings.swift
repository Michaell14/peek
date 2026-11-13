import Foundation

public enum ColorSchemePreference: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// Which display the overlay opens on.
public struct DisplayTarget: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// The display the pointer is on.
        case pointer
        /// The display with the window that has keyboard focus.
        case active
        /// Always the same display.
        case fixed
    }

    public var kind: Kind
    /// Stable identifier of the chosen display when `kind` is `.fixed`.
    public var displayKey: String?

    public init(kind: Kind = .pointer, displayKey: String? = nil) {
        self.kind = kind
        self.displayKey = displayKey
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.value(.kind, default: .pointer)
        displayKey = (try? c.decodeIfPresent(String.self, forKey: .displayKey)) ?? nil
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var shortcut: Shortcut
    /// A press shorter than this (seconds) keeps the overlay open.
    public var tapThreshold: Double
    /// One layout everywhere, or a separate layout per display.
    public var syncAcrossDisplays: Bool
    public var displayTarget: DisplayTarget

    public var backdropOpacity: Double
    public var backdropBlur: Bool
    public var tileCornerRadius: Double
    public var tileGap: Double
    public var canvasPadding: Double
    public var fadeDuration: Double

    public var blockAds: Bool
    public var blockTrackers: Bool
    public var hideCookieBanners: Bool
    /// Extra rules in Adblock Plus syntax, one per line.
    public var customFilters: String
    public var webColorScheme: ColorSchemePreference
    public var searchTemplate: String

    /// Ask GitHub once a day whether there is a newer Blink.
    public var checksForUpdates: Bool

    /// True once a saved fn (the default in 0.1.2) has been moved back to
    /// ⌥`, so that someone who picks fn in Settings afterwards keeps it.
    public var shortcutMovedBack: Bool

    public init() {
        shortcut = .default
        tapThreshold = 0.3
        syncAcrossDisplays = true
        displayTarget = DisplayTarget()
        backdropOpacity = 0.32
        backdropBlur = true
        tileCornerRadius = 18
        tileGap = 14
        canvasPadding = 28
        fadeDuration = 0.14
        blockAds = true
        blockTrackers = true
        hideCookieBanners = true
        customFilters = ""
        webColorScheme = .system
        searchTemplate = URLInput.defaultSearchTemplate
        checksForUpdates = true
        shortcutMovedBack = true
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        shortcut = c.value(.shortcut, default: d.shortcut)
        if !shortcut.isValid { shortcut = d.shortcut }
        // fn was the default for a while. Move it back to ⌥` once; a choice
        // made after that is kept.
        if !c.value(.shortcutMovedBack, default: false), shortcut == .functionKey {
            shortcut = d.shortcut
        }
        shortcutMovedBack = true
        tapThreshold = min(max(c.value(.tapThreshold, default: d.tapThreshold), 0.1), 1)
        syncAcrossDisplays = c.value(.syncAcrossDisplays, default: d.syncAcrossDisplays)
        displayTarget = c.value(.displayTarget, default: d.displayTarget)
        backdropOpacity = min(max(c.value(.backdropOpacity, default: d.backdropOpacity), 0), 1)
        backdropBlur = c.value(.backdropBlur, default: d.backdropBlur)
        tileCornerRadius = min(max(c.value(.tileCornerRadius, default: d.tileCornerRadius), 0), 40)
        tileGap = min(max(c.value(.tileGap, default: d.tileGap), 0), 60)
        canvasPadding = min(max(c.value(.canvasPadding, default: d.canvasPadding), 0), 200)
        fadeDuration = min(max(c.value(.fadeDuration, default: d.fadeDuration), 0), 1)
        blockAds = c.value(.blockAds, default: d.blockAds)
        blockTrackers = c.value(.blockTrackers, default: d.blockTrackers)
        hideCookieBanners = c.value(.hideCookieBanners, default: d.hideCookieBanners)
        customFilters = c.value(.customFilters, default: d.customFilters)
        webColorScheme = c.value(.webColorScheme, default: d.webColorScheme)
        searchTemplate = c.value(.searchTemplate, default: d.searchTemplate)
        if !searchTemplate.contains("%s") { searchTemplate = d.searchTemplate }
        checksForUpdates = c.value(.checksForUpdates, default: d.checksForUpdates)
    }

    public var contentBlocking: ContentBlocker.Options {
        ContentBlocker.Options(
            blockAds: blockAds,
            blockTrackers: blockTrackers,
            hideCookieBanners: hideCookieBanners
        )
    }
}
