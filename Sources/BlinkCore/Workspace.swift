import Foundation

/// Everything the app persists: settings, boards, and which board each
/// display shows.
public struct Workspace: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var settings: AppSettings
    public var boards: [Board]
    /// The board used on every display while layouts are synced.
    public var sharedBoardID: UUID
    /// Display identifier -> board, used when each display has its own layout.
    public var displayBoards: [String: UUID]

    public init(settings: AppSettings = AppSettings(), board: Board) {
        schemaVersion = Workspace.currentSchemaVersion
        self.settings = settings
        boards = [board]
        sharedBoardID = board.id
        displayBoards = [:]
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.value(.schemaVersion, default: Workspace.currentSchemaVersion)
        settings = c.value(.settings, default: AppSettings())
        boards = c.value(.boards, default: [])
        displayBoards = c.value(.displayBoards, default: [:])
        sharedBoardID = c.value(.sharedBoardID, default: boards.first?.id ?? UUID())
        repair()
    }

    /// A first-run workspace with something to look at.
    public static func makeDefault() -> Workspace {
        let welcome = """
        Welcome to Blink.

        • Hold ⌥` (Option and the key above Tab) to peek. Let go to return to work.
        • Tap it instead to keep this open and use it.
        • Press + to add websites, PDFs and widgets.
        • Press Edit to move and resize tiles.

        You can change the shortcut in Settings (the gear, top right).
        """
        var tiles = [
            Tile(content: .widget(.clock(ClockConfig(zones: [ClockConfig.localZone, "Europe/London", "Asia/Tokyo"])))),
            Tile(content: .widget(.notes(NotesConfig(text: welcome)))),
        ]
        if let url = URL(string: "https://en.m.wikipedia.org/wiki/Main_Page") {
            tiles.append(Tile(content: .web(WebContent(url: url))))
        }
        return Workspace(board: Board(name: "Main", mode: .flow, tiles: tiles))
    }

    // MARK: - Boards

    public func board(_ id: UUID) -> Board? {
        boards.first { $0.id == id }
    }

    /// The board a display should show under the current sync setting, if one
    /// has been assigned.
    public func boardID(forDisplay key: String) -> UUID? {
        if settings.syncAcrossDisplays { return sharedBoardID }
        guard let id = displayBoards[key], board(id) != nil else { return nil }
        return id
    }

    /// Like `boardID(forDisplay:)`, but gives a display that has never been
    /// used its own copy of the shared layout to start from.
    public mutating func ensureBoard(forDisplay key: String, name: String) -> UUID {
        if let id = boardID(forDisplay: key) { return id }
        var copy = board(sharedBoardID) ?? Board(name: name)
        copy.id = UUID()
        copy.name = name
        copy.tiles = copy.tiles.map { tile in
            var fresh = tile
            fresh.id = UUID()
            return fresh
        }
        boards.append(copy)
        displayBoards[key] = copy.id
        return copy.id
    }

    public mutating func updateBoard(_ id: UUID, _ change: (inout Board) -> Void) {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return }
        change(&boards[index])
    }

    // MARK: - Tiles

    public mutating func addTile(_ tile: Tile, to boardID: UUID) {
        updateBoard(boardID) { $0.tiles.append(tile) }
    }

    public mutating func removeTile(_ tileID: UUID, from boardID: UUID) {
        updateBoard(boardID) { board in
            board.tiles.removeAll { $0.id == tileID }
        }
    }

    public mutating func updateTile(_ tileID: UUID, in boardID: UUID, _ change: (inout Tile) -> Void) {
        updateBoard(boardID) { board in
            guard let index = board.tiles.firstIndex(where: { $0.id == tileID }) else { return }
            change(&board.tiles[index])
        }
    }

    /// Moves a tile to `index`, counted with the tile itself taken out.
    public mutating func moveTile(_ tileID: UUID, in boardID: UUID, to index: Int) {
        updateBoard(boardID) { board in
            guard let from = board.tiles.firstIndex(where: { $0.id == tileID }) else { return }
            let tile = board.tiles.remove(at: from)
            board.tiles.insert(tile, at: min(max(index, 0), board.tiles.count))
        }
    }

    public mutating func bringTileToFront(_ tileID: UUID, in boardID: UUID) {
        updateBoard(boardID) { board in
            guard let from = board.tiles.firstIndex(where: { $0.id == tileID }),
                  from != board.tiles.count - 1 else { return }
            board.tiles.append(board.tiles.remove(at: from))
        }
    }

    // MARK: - Private

    /// Puts a decoded workspace back into a usable shape.
    private mutating func repair() {
        if boards.isEmpty {
            boards = [Board(name: "Main")]
        }
        if board(sharedBoardID) == nil {
            sharedBoardID = boards[0].id
        }
        displayBoards = displayBoards.filter { board($0.value) != nil }
        schemaVersion = Workspace.currentSchemaVersion
    }
}
