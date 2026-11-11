import XCTest
@testable import BlickCore

final class WorkspaceTests: XCTestCase {
    private func webTile(_ address: String = "https://example.com") -> Tile {
        Tile(content: .web(WebContent(url: URL(string: address)!)))
    }

    func testDefaultWorkspaceIsUsable() {
        let workspace = Workspace.makeDefault()
        XCTAssertEqual(workspace.boards.count, 1)
        XCTAssertEqual(workspace.sharedBoardID, workspace.boards[0].id)
        XCTAssertFalse(workspace.boards[0].tiles.isEmpty)
        XCTAssertEqual(workspace.settings.shortcut, .default)
    }

    func testRoundTripPreservesEverything() throws {
        var workspace = Workspace.makeDefault()
        let boardID = workspace.sharedBoardID
        var web = WebContent(url: URL(string: "https://example.com/a?b=c")!)
        web.refreshInterval = 300
        web.zoom = 0.8
        web.prefersMobileSite = true
        web.hiddenElements = [HiddenElement(host: "example.com", selector: "div > .ad")]
        var tile = Tile(content: .web(web), frame: LayoutRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        tile.flowWidth = 512
        tile.flowHeight = 300
        workspace.addTile(tile, to: boardID)
        workspace.addTile(Tile(content: .file(FileContent(path: "/tmp/report.pdf", kind: .pdf))), to: boardID)
        workspace.addTile(Tile(content: .widget(.calendar(CalendarConfig(mode: .agenda)))), to: boardID)
        workspace.addTile(Tile(content: .widget(.reminders(RemindersConfig(filter: .overdue)))), to: boardID)
        workspace.settings.shortcut = Shortcut(keyCode: nil, modifiers: [ModifierKey(.command, side: .right)])
        workspace.settings.syncAcrossDisplays = false
        workspace.settings.displayTarget = DisplayTarget(kind: .fixed, displayKey: "ABC")
        workspace.settings.customFilters = "||ads.example.com^"
        _ = workspace.ensureBoard(forDisplay: "ABC", name: "Studio Display")

        let data = try JSONEncoder().encode(workspace)
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: data), workspace)
    }

    func testMissingFieldsFallBackToDefaults() throws {
        let json = """
        {"boards":[{"tiles":[{"content":{"type":"web","web":{"url":"https://example.com"}}}]}]}
        """
        let workspace = try JSONDecoder().decode(Workspace.self, from: Data(json.utf8))
        XCTAssertEqual(workspace.settings, AppSettings())
        XCTAssertEqual(workspace.boards.count, 1)
        XCTAssertEqual(workspace.sharedBoardID, workspace.boards[0].id)
        let tile = try XCTUnwrap(workspace.boards[0].tiles.first)
        guard case .web(let web) = tile.content else { return XCTFail("expected a web tile") }
        XCTAssertEqual(web.zoom, 1)
        XCTAssertEqual(web.refreshInterval, 0)
        XCTAssertEqual(tile.flowWidth, 460)
        XCTAssertNil(tile.flowHeight)
    }

    /// A tile written by a newer version must not cost the user their board.
    func testUnknownTileKindsAreDroppedButTheRestSurvive() throws {
        let json = """
        {"boards":[{"name":"Main","tiles":[
          {"content":{"type":"hologram","hologram":{}}},
          {"content":{"type":"widget","widget":{"kind":"clock"}}},
          {"content":{"type":"widget","widget":{"kind":"lava-lamp"}}}
        ]}]}
        """
        let workspace = try JSONDecoder().decode(Workspace.self, from: Data(json.utf8))
        XCTAssertEqual(workspace.boards[0].tiles.count, 1)
        XCTAssertEqual(workspace.boards[0].tiles[0].content, .widget(.clock(ClockConfig())))
    }

    func testOutOfRangeSettingsAreClamped() throws {
        let json = """
        {"settings":{"tapThreshold":99,"backdropOpacity":-3,"tileGap":1000,
                     "searchTemplate":"https://nowhere.example/","shortcut":{"modifiers":[]}}}
        """
        let settings = try JSONDecoder().decode(Workspace.self, from: Data(json.utf8)).settings
        XCTAssertEqual(settings.tapThreshold, 1)
        XCTAssertEqual(settings.backdropOpacity, 0)
        XCTAssertEqual(settings.tileGap, 60)
        XCTAssertEqual(settings.searchTemplate, URLInput.defaultSearchTemplate)
        XCTAssertEqual(settings.shortcut, .default, "an empty shortcut could never be pressed")
    }

    func testDanglingReferencesAreRepaired() throws {
        let json = """
        {"boards":[],"sharedBoardID":"\(UUID().uuidString)","displayBoards":{"X":"\(UUID().uuidString)"}}
        """
        let workspace = try JSONDecoder().decode(Workspace.self, from: Data(json.utf8))
        XCTAssertEqual(workspace.boards.count, 1)
        XCTAssertEqual(workspace.sharedBoardID, workspace.boards[0].id)
        XCTAssertTrue(workspace.displayBoards.isEmpty)
    }

    func testTileMutations() {
        var workspace = Workspace(board: Board(name: "Main"))
        let board = workspace.sharedBoardID
        let a = webTile(), b = webTile(), c = webTile()
        [a, b, c].forEach { workspace.addTile($0, to: board) }

        workspace.moveTile(c.id, in: board, to: 0)
        XCTAssertEqual(workspace.board(board)?.tiles.map(\.id), [c.id, a.id, b.id])
        workspace.moveTile(c.id, in: board, to: 99)
        XCTAssertEqual(workspace.board(board)?.tiles.map(\.id), [a.id, b.id, c.id])

        workspace.bringTileToFront(a.id, in: board)
        XCTAssertEqual(workspace.board(board)?.tiles.map(\.id), [b.id, c.id, a.id])

        workspace.updateTile(b.id, in: board) { $0.flowWidth = 999 }
        XCTAssertEqual(workspace.board(board)?.tile(b.id)?.flowWidth, 999)

        workspace.removeTile(b.id, from: board)
        XCTAssertEqual(workspace.board(board)?.tiles.map(\.id), [c.id, a.id])

        // Unknown ids are ignored rather than trapping.
        workspace.removeTile(UUID(), from: board)
        workspace.updateTile(UUID(), in: UUID()) { $0.flowWidth = 1 }
        workspace.moveTile(UUID(), in: board, to: 0)
        XCTAssertEqual(workspace.board(board)?.tiles.count, 2)
    }

    func testSyncedDisplaysShareOneBoard() {
        var workspace = Workspace.makeDefault()
        XCTAssertEqual(workspace.ensureBoard(forDisplay: "A", name: "A"), workspace.sharedBoardID)
        XCTAssertEqual(workspace.ensureBoard(forDisplay: "B", name: "B"), workspace.sharedBoardID)
        XCTAssertEqual(workspace.boards.count, 1)
    }

    func testPerDisplayBoardsStartAsIndependentCopies() throws {
        var workspace = Workspace.makeDefault()
        workspace.settings.syncAcrossDisplays = false
        XCTAssertNil(workspace.boardID(forDisplay: "A"))

        let a = workspace.ensureBoard(forDisplay: "A", name: "Built-in")
        XCTAssertNotEqual(a, workspace.sharedBoardID)
        XCTAssertEqual(workspace.ensureBoard(forDisplay: "A", name: "Built-in"), a, "second call reuses the board")
        XCTAssertNotEqual(workspace.ensureBoard(forDisplay: "B", name: "External"), a)

        let shared = try XCTUnwrap(workspace.board(workspace.sharedBoardID))
        let copy = try XCTUnwrap(workspace.board(a))
        XCTAssertEqual(copy.name, "Built-in")
        XCTAssertEqual(copy.tiles.map(\.content), shared.tiles.map(\.content))
        XCTAssertTrue(Set(copy.tiles.map(\.id)).isDisjoint(with: shared.tiles.map(\.id)), "copies need their own ids")

        workspace.removeTile(copy.tiles[0].id, from: a)
        XCTAssertEqual(workspace.board(workspace.sharedBoardID)?.tiles.count, shared.tiles.count)
    }

    func testClockTilesAreSizedToTheirCities() {
        let one = Tile(content: .widget(.clock(ClockConfig(zones: ["local"]))))
        let three = Tile(content: .widget(.clock(ClockConfig(zones: ["local", "Europe/London", "Asia/Tokyo"]))))
        XCTAssertEqual(one.flowHeight, 100)
        XCTAssertEqual(three.flowHeight, 220)
        let many = Tile(content: .widget(.clock(ClockConfig(zones: Array(repeating: "UTC", count: 30)))))
        XCTAssertEqual(many.flowHeight, 520, "a long list scrolls instead of growing without limit")
    }

    func testFileContentKinds() {
        XCTAssertEqual(FileContent(path: "/a/b/Report.PDF")?.kind, .pdf)
        XCTAssertEqual(FileContent(path: "/a/index.htm")?.kind, .html)
        XCTAssertEqual(FileContent(path: "/a/b/Report.PDF")?.fileName, "Report.PDF")
        XCTAssertNil(FileContent(path: "/a/notes.txt"))
        XCTAssertNil(FileContent(path: "/a/noextension"))
    }
}

final class WorkspaceStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("blick-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testMissingFile() {
        guard case .missing = WorkspaceStore(directory: directory).load() else {
            return XCTFail("expected .missing")
        }
    }

    func testSaveCreatesDirectoriesAndLoadsBack() throws {
        let store = WorkspaceStore(directory: directory.appendingPathComponent("nested/deeper"))
        let workspace = Workspace.makeDefault()
        try store.save(workspace)
        guard case .loaded(let loaded) = store.load() else { return XCTFail("expected .loaded") }
        XCTAssertEqual(loaded, workspace)
    }

    /// An unreadable file is set aside, never silently replaced.
    func testCorruptFileIsPreserved() throws {
        let store = WorkspaceStore(directory: directory)
        try Data("{ not json".utf8).write(to: store.fileURL)

        guard case .corrupt(let backup) = store.load() else { return XCTFail("expected .corrupt") }
        let backupURL = try XCTUnwrap(backup)
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), "{ not json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))

        try store.save(Workspace.makeDefault())
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path), "saving must not touch the backup")
    }
}
