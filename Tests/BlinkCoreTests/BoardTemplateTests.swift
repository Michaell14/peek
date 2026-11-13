import XCTest
@testable import BlinkCore

final class BoardTemplateTests: XCTestCase {
    /// A 14-inch laptop's canvas, and a small 13-inch one.
    private let laptop = LayoutSize(width: 1400, height: 820)
    private let small = LayoutSize(width: 1220, height: 740)
    private let options = FlowLayout.Options(gap: 12, minWidth: 180, minHeight: 90)

    func testThereAreAFewTemplatesWithDistinctNames() {
        XCTAssertGreaterThanOrEqual(BoardTemplate.all.count, 5)
        XCTAssertEqual(Set(BoardTemplate.all.map(\.id)).count, BoardTemplate.all.count)
        XCTAssertEqual(Set(BoardTemplate.all.map(\.name)).count, BoardTemplate.all.count)
    }

    func testMyDayIsCalendarThenMessagesThenRemindersAndANote() throws {
        let day = try XCTUnwrap(BoardTemplate.all.first { $0.id == "day" })
        let columns = FlowLayout.columns(for: day.flowItems)
        XCTAssertEqual(columns.count, 3)
        let tiles = day.makeTiles()
        XCTAssertEqual(tiles.map(\.content.kindName), ["calendar", "messages", "reminders", "notes"])
        XCTAssertEqual(columns.map(\.count), [1, 1, 2])
    }

    func testEveryTemplateLaysOutWithoutSqueezingOnALaptop() {
        for template in BoardTemplate.all {
            let items = template.flowItems
            let frames = FlowLayout.layout(items, in: laptop, options: options)
            XCTAssertEqual(frames.count, items.count, template.name)
            for item in items {
                let frame = frames[item.id]!
                XCTAssertEqual(frame.width, item.width, accuracy: 1, "\(template.name) is too wide for a laptop")
                if let height = item.height {
                    XCTAssertEqual(frame.height, height, accuracy: 1, "\(template.name) is too tall for a laptop")
                }
                XCTAssertGreaterThanOrEqual(frame.height, 200, "\(template.name) leaves a tile too short to use")
            }
        }
    }

    func testEveryTemplateStillFitsASmallScreen() {
        for template in BoardTemplate.all {
            let frames = FlowLayout.layout(template.flowItems, in: small, options: options)
            for frame in frames.values {
                XCTAssertGreaterThanOrEqual(frame.minX, 0, template.name)
                XCTAssertLessThanOrEqual(frame.maxX, small.width + 0.5, template.name)
                XCTAssertLessThanOrEqual(frame.maxY, small.height + 0.5, template.name)
                XCTAssertGreaterThanOrEqual(frame.height, 150, template.name)
            }
        }
    }

    func testEachUseMakesFreshTiles() throws {
        let template = try XCTUnwrap(BoardTemplate.all.first)
        let first = template.makeTiles(), second = template.makeTiles()
        XCTAssertTrue(Set(first.map(\.id)).isDisjoint(with: second.map(\.id)))
        XCTAssertTrue(Set(first.map(\.column)).isDisjoint(with: second.map(\.column)))
    }

    func testApplyingATemplateReplacesTheBoard() throws {
        var workspace = Workspace.makeDefault()
        let board = workspace.sharedBoardID
        let template = try XCTUnwrap(BoardTemplate.all.first { $0.id == "markets" })
        workspace.applyTemplate(template, to: board)
        let tiles = try XCTUnwrap(workspace.board(board)?.tiles)
        XCTAssertEqual(tiles.count, template.columns.flatMap { $0 }.count)
        XCTAssertTrue(tiles.contains { if case .web(let web) = $0.content { return web.refreshInterval == 300 } else { return false } })
        // Saved and read back, it is the same board.
        let data = try JSONEncoder().encode(workspace)
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: data), workspace)
    }

    func testWebsitesInTemplatesHaveRealAddresses() {
        for template in BoardTemplate.all {
            for tile in template.makeTiles() {
                if case .web(let web) = tile.content {
                    XCTAssertEqual(web.url.scheme, "https", template.name)
                    XCTAssertNotNil(web.url.host, template.name)
                }
            }
        }
    }
}

private extension TileContent {
    var kindName: String {
        switch self {
        case .web: return "web"
        case .file: return "file"
        case .widget(let widget): return widget.displayName.lowercased()
        }
    }
}
