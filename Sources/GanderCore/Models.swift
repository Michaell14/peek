import Foundation

extension KeyedDecodingContainer {
    /// Decodes a value, falling back to `fallback` when the key is missing or
    /// malformed. Saved workspaces must keep loading as fields come and go.
    func value<T: Decodable>(_ key: Key, default fallback: @autoclosure () -> T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback()
    }
}

/// Decodes to nil instead of throwing, so one bad element cannot fail an array.
struct Lossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

// MARK: - Layout

public enum LayoutMode: String, Codable, CaseIterable, Sendable {
    /// Tiles sit wherever the user dragged them.
    case freeform
    /// Tiles are packed into full-height columns in order.
    case flow
}

// MARK: - Web

/// A page element the user chose to hide, scoped to the site it was picked on.
public struct HiddenElement: Codable, Hashable, Sendable {
    public var host: String
    public var selector: String

    public init(host: String, selector: String) {
        self.host = host
        self.selector = selector
    }
}

public struct WebContent: Codable, Hashable, Sendable {
    /// The page the tile opens to and returns to.
    public var url: URL
    /// Seconds between automatic reloads; zero turns auto-refresh off.
    public var refreshInterval: Double
    public var zoom: Double
    public var hiddenElements: [HiddenElement]
    public var prefersMobileSite: Bool

    public init(
        url: URL,
        refreshInterval: Double = 0,
        zoom: Double = 1,
        hiddenElements: [HiddenElement] = [],
        prefersMobileSite: Bool = false
    ) {
        self.url = url
        self.refreshInterval = refreshInterval
        self.zoom = zoom
        self.hiddenElements = hiddenElements
        self.prefersMobileSite = prefersMobileSite
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(URL.self, forKey: .url)
        refreshInterval = c.value(.refreshInterval, default: 0)
        zoom = c.value(.zoom, default: 1)
        hiddenElements = c.value(.hiddenElements, default: [])
        prefersMobileSite = c.value(.prefersMobileSite, default: false)
    }
}

// MARK: - Files

public struct FileContent: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case pdf
        case html
    }

    public var path: String
    public var kind: Kind

    public init(path: String, kind: Kind) {
        self.path = path
        self.kind = kind
    }

    /// Returns nil for file types the app cannot display.
    public init?(path: String) {
        switch (path as NSString).pathExtension.lowercased() {
        case "pdf": self.init(path: path, kind: .pdf)
        case "html", "htm", "xhtml": self.init(path: path, kind: .html)
        default: return nil
        }
    }

    public var fileName: String { (path as NSString).lastPathComponent }
}

// MARK: - Widgets

public struct ClockConfig: Codable, Hashable, Sendable {
    /// IANA identifiers such as "Europe/London"; "local" means the Mac's own zone.
    public var zones: [String]

    public init(zones: [String] = [ClockConfig.localZone]) {
        self.zones = zones
    }

    public static let localZone = "local"

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        zones = c.value(.zones, default: [ClockConfig.localZone])
    }
}

public struct CalendarConfig: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case day
        case agenda
    }

    public var mode: Mode

    public init(mode: Mode = .day) {
        self.mode = mode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = c.value(.mode, default: .day)
    }
}

public struct RemindersConfig: Codable, Hashable, Sendable {
    public enum Filter: String, Codable, CaseIterable, Sendable {
        case today
        case scheduled
        case overdue
        case all
    }

    public var filter: Filter

    public init(filter: Filter = .today) {
        self.filter = filter
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filter = c.value(.filter, default: .today)
    }
}

public struct NotesConfig: Codable, Hashable, Sendable {
    public var text: String

    public init(text: String = "") {
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = c.value(.text, default: "")
    }
}

public enum WidgetContent: Hashable, Sendable {
    case clock(ClockConfig)
    case calendar(CalendarConfig)
    case reminders(RemindersConfig)
    case notes(NotesConfig)

    public var displayName: String {
        switch self {
        case .clock: return "Clock"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .notes: return "Notes"
        }
    }
}

extension WidgetContent: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, config
    }

    private enum Kind: String, Codable {
        case clock, calendar, reminders, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .clock: self = .clock(c.value(.config, default: ClockConfig()))
        case .calendar: self = .calendar(c.value(.config, default: CalendarConfig()))
        case .reminders: self = .reminders(c.value(.config, default: RemindersConfig()))
        case .notes: self = .notes(c.value(.config, default: NotesConfig()))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .clock(let config):
            try c.encode(Kind.clock, forKey: .kind)
            try c.encode(config, forKey: .config)
        case .calendar(let config):
            try c.encode(Kind.calendar, forKey: .kind)
            try c.encode(config, forKey: .config)
        case .reminders(let config):
            try c.encode(Kind.reminders, forKey: .kind)
            try c.encode(config, forKey: .config)
        case .notes(let config):
            try c.encode(Kind.notes, forKey: .kind)
            try c.encode(config, forKey: .config)
        }
    }
}

// MARK: - Tiles

public enum TileContent: Hashable, Sendable {
    case web(WebContent)
    case file(FileContent)
    case widget(WidgetContent)
}

extension TileContent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, web, file, widget
    }

    private enum Kind: String, Codable {
        case web, file, widget
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .web: self = .web(try c.decode(WebContent.self, forKey: .web))
        case .file: self = .file(try c.decode(FileContent.self, forKey: .file))
        case .widget: self = .widget(try c.decode(WidgetContent.self, forKey: .widget))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .web(let web):
            try c.encode(Kind.web, forKey: .type)
            try c.encode(web, forKey: .web)
        case .file(let file):
            try c.encode(Kind.file, forKey: .type)
            try c.encode(file, forKey: .file)
        case .widget(let widget):
            try c.encode(Kind.widget, forKey: .type)
            try c.encode(widget, forKey: .widget)
        }
    }
}

public struct Tile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var content: TileContent
    /// Freeform placement as fractions of the canvas (0...1), so a layout
    /// survives a change of display or resolution.
    public var frame: Rect
    /// Preferred width in points when the board is in flow mode.
    public var flowWidth: Double
    /// Preferred height in points in flow mode; nil fills the column.
    public var flowHeight: Double?

    public init(id: UUID = UUID(), content: TileContent, frame: Rect? = nil) {
        self.id = id
        self.content = content
        let defaults = Tile.defaultSizing(for: content)
        self.frame = frame ?? Rect(x: 0.05, y: 0.05, width: 0.3, height: 0.6)
        self.flowWidth = defaults.width
        self.flowHeight = defaults.height
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        content = try c.decode(TileContent.self, forKey: .content)
        let defaults = Tile.defaultSizing(for: content)
        frame = c.value(.frame, default: Rect(x: 0.05, y: 0.05, width: 0.3, height: 0.6))
        flowWidth = c.value(.flowWidth, default: defaults.width)
        flowHeight = (try? c.decodeIfPresent(Double.self, forKey: .flowHeight)) ?? nil
    }

    /// Natural size, in points, for a freshly added tile of this kind.
    /// A nil height means "as tall as the canvas allows".
    public static func defaultSizing(for content: TileContent) -> (width: Double, height: Double?) {
        switch content {
        case .web: return (460, nil)
        case .file: return (520, nil)
        case .widget(.clock): return (280, 150)
        case .widget(.calendar): return (300, nil)
        case .widget(.reminders): return (300, 360)
        case .widget(.notes): return (300, 240)
        }
    }
}

public struct Board: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var mode: LayoutMode
    /// In flow mode this is the packing order; in freeform it is back-to-front.
    public var tiles: [Tile]

    public init(id: UUID = UUID(), name: String, mode: LayoutMode = .flow, tiles: [Tile] = []) {
        self.id = id
        self.name = name
        self.mode = mode
        self.tiles = tiles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "Board")
        mode = c.value(.mode, default: .flow)
        // One unreadable tile (say, a kind added by a newer version) must not
        // take the rest of the board down with it.
        tiles = c.value(.tiles, default: [Lossy<Tile>]()).compactMap(\.value)
    }

    public func tile(_ id: UUID) -> Tile? {
        tiles.first { $0.id == id }
    }
}
