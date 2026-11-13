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

/// The Messages widget keeps nothing of its own yet; conversations are read
/// from Messages each time.
public struct MessagesConfig: Codable, Hashable, Sendable {
    public init() {}
}

public enum WidgetContent: Hashable, Sendable {
    case clock(ClockConfig)
    case calendar(CalendarConfig)
    case reminders(RemindersConfig)
    case notes(NotesConfig)
    case messages(MessagesConfig)

    public var displayName: String {
        switch self {
        case .clock: return "Clock"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .notes: return "Notes"
        case .messages: return "Messages"
        }
    }
}

extension WidgetContent: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, config
    }

    private enum Kind: String, Codable {
        case clock, calendar, reminders, notes, messages
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .clock: self = .clock(c.value(.config, default: ClockConfig()))
        case .calendar: self = .calendar(c.value(.config, default: CalendarConfig()))
        case .reminders: self = .reminders(c.value(.config, default: RemindersConfig()))
        case .notes: self = .notes(c.value(.config, default: NotesConfig()))
        case .messages: self = .messages(c.value(.config, default: MessagesConfig()))
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
        case .messages(let config):
            try c.encode(Kind.messages, forKey: .kind)
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
    /// Preferred width in points; columns are as wide as their widest tile.
    public var flowWidth: Double
    /// Height in points; nil fills what is left of the column.
    public var flowHeight: Double?
    /// Neighbouring tiles with the same column are stacked in it. A new
    /// tile starts a column of its own.
    public var column: UUID
    /// Empty space in points kept above the tile, left when its top edge was
    /// pulled down.
    public var spaceAbove: Double

    public init(id: UUID = UUID(), content: TileContent) {
        self.id = id
        self.content = content
        let defaults = Tile.defaultSizing(for: content)
        self.flowWidth = defaults.width
        self.flowHeight = defaults.height
        self.column = UUID()
        self.spaceAbove = 0
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        content = try c.decode(TileContent.self, forKey: .content)
        let defaults = Tile.defaultSizing(for: content)
        flowWidth = c.value(.flowWidth, default: defaults.width)
        flowHeight = (try? c.decodeIfPresent(Double.self, forKey: .flowHeight)) ?? nil
        column = c.value(.column, default: UUID())
        spaceAbove = c.value(.spaceAbove, default: 0)
    }

    /// The tile as the layout sees it.
    public var flowItem: FlowLayout.Item {
        FlowLayout.Item(id: id, width: flowWidth, height: flowHeight, column: column, spaceAbove: spaceAbove)
    }

    /// Natural size, in points, for a freshly added tile of this kind.
    /// A nil height means "as tall as the canvas allows".
    public static func defaultSizing(for content: TileContent) -> (width: Double, height: Double?) {
        switch content {
        case .web: return (460, nil)
        case .file: return (520, nil)
        case .widget(.clock(let config)):
            // One row per city, plus the "add city" row.
            let rows = Double(min(max(config.zones.count, 1), 8))
            return (280, rows * 60 + 40)
        case .widget(.calendar): return (300, nil)
        case .widget(.reminders): return (300, 360)
        case .widget(.notes): return (300, 240)
        case .widget(.messages): return (320, nil)
        }
    }
}

public struct Board: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// The order tiles are packed into columns.
    public var tiles: [Tile]

    public init(id: UUID = UUID(), name: String, tiles: [Tile] = []) {
        self.id = id
        self.name = name
        self.tiles = tiles
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, tiles
        /// Only in boards saved before Freeform was removed.
        case mode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "Board")
        // One unreadable tile (say, a kind added by a newer version) must not
        // take the rest of the board down with it.
        let saved = c.value(.tiles, default: [Lossy<SavedTile>]()).compactMap(\.value)
        if c.value(.mode, default: "flow") == "freeform" {
            tiles = Board.columns(fromFreeform: saved)
        } else if saved.contains(where: { !$0.hasColumn }) {
            tiles = Board.columns(fromAutomaticStacking: saved.map(\.tile))
        } else {
            tiles = saved.map(\.tile)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(tiles, forKey: .tiles)
    }

    /// A tile as saved, with what older versions saved about where it went.
    private struct SavedTile: Decodable {
        let tile: Tile
        /// Where it sat on a Freeform board.
        let freeformFrame: LayoutRect?
        /// False for tiles saved before columns were kept.
        let hasColumn: Bool

        private enum Key: String, CodingKey { case frame, column }

        init(from decoder: Decoder) throws {
            tile = try Tile(from: decoder)
            let c = try? decoder.container(keyedBy: Key.self)
            freeformFrame = try? c?.decodeIfPresent(LayoutRect.self, forKey: .frame)
            hasColumn = c?.contains(.column) ?? false
        }
    }

    /// The canvas a Freeform board is read off when it becomes columns: a
    /// typical laptop screen, since the real one is not known yet.
    static let migrationCanvas = LayoutSize(width: 1440, height: 840)

    /// Blink used to have a Freeform mode, where tiles sat wherever they were
    /// dragged. A board saved that way opens as columns that follow where its
    /// tiles were: left to right, top to bottom, at about the same widths.
    private static func columns(fromFreeform saved: [SavedTile]) -> [Tile] {
        let canvas = migrationCanvas
        let frames = saved.map { item -> (id: UUID, rect: LayoutRect) in
            let unit = item.freeformFrame ?? LayoutRect(x: 0, y: 0, width: 0.3, height: 1)
            return (item.tile.id, unit.scaled(to: canvas))
        }
        let items = FlowLayout.items(from: frames, canvasHeight: canvas.height)
        let byID = Dictionary(saved.map { ($0.tile.id, $0.tile) }, uniquingKeysWith: { first, _ in first })
        return items.compactMap { item in
            guard var tile = byID[item.id] else { return nil }
            tile.flowWidth = max(item.width.rounded(), 160)
            tile.flowHeight = item.height?.rounded()
            tile.column = item.column
            tile.spaceAbove = item.spaceAbove.rounded()
            return tile
        }
    }

    /// Before tiles were stacked by hand, a tile went under the one before it
    /// whenever it fitted there, and the bottom tile of every column was
    /// stretched to the bottom. A board saved then keeps that arrangement,
    /// worked out for the canvas of a typical laptop screen.
    private static func columns(fromAutomaticStacking tiles: [Tile]) -> [Tile] {
        let available = migrationCanvas.height
        let options = FlowLayout.Options()
        var result: [Tile] = []
        var used = 0.0
        var columnFills = false
        var column = UUID()
        for var tile in tiles {
            let height = tile.flowHeight.map { min(max($0, options.minHeight), available) }
            if let height, !result.isEmpty, !columnFills, used + options.gap + height <= available + 0.5 {
                used += options.gap + height
            } else {
                if !result.isEmpty { result[result.count - 1].flowHeight = nil }
                column = UUID()
                columnFills = height == nil
                used = height ?? available
            }
            tile.column = column
            result.append(tile)
        }
        if !result.isEmpty { result[result.count - 1].flowHeight = nil }
        return result
    }

    public func tile(_ id: UUID) -> Tile? {
        tiles.first { $0.id == id }
    }
}
