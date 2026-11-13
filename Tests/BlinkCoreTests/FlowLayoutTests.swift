import XCTest
@testable import BlinkCore

final class FlowLayoutTests: XCTestCase {
    private let canvas = LayoutSize(width: 1400, height: 800)
    private let options = FlowLayout.Options(gap: 10, minWidth: 100, minHeight: 50)

    private func item(_ width: Double, _ height: Double?, column: UUID = UUID()) -> FlowLayout.Item {
        FlowLayout.Item(id: UUID(), width: width, height: height, column: column)
    }

    func testEmptyInput() {
        XCTAssertTrue(FlowLayout.layout([], in: canvas, options: options).isEmpty)
        XCTAssertTrue(FlowLayout.layout([item(100, nil)], in: .zero, options: options).isEmpty)
    }

    func testFillTilesGetTheirOwnFullHeightColumns() {
        let a = item(400, nil), b = item(300, nil)
        let frames = FlowLayout.layout([a, b], in: canvas, options: options)
        // 400 + 10 + 300 = 710 wide, centred in 1400.
        XCTAssertEqual(frames[a.id], LayoutRect(x: 345, y: 0, width: 400, height: 800))
        XCTAssertEqual(frames[b.id], LayoutRect(x: 755, y: 0, width: 300, height: 800))
    }

    func testATileOnItsOwnKeepsItsHeight() {
        let clock = item(280, 220)
        XCTAssertEqual(FlowLayout.layout([clock], in: canvas, options: options)[clock.id]?.height, 220)
    }

    func testTilesInAColumnStackAndKeepTheirHeights() {
        let column = UUID()
        let clock = item(280, 150, column: column), notes = item(300, 240, column: column), web = item(400, nil)
        let frames = FlowLayout.layout([clock, notes, web], in: canvas, options: options)
        let clockFrame = frames[clock.id]!, notesFrame = frames[notes.id]!, webFrame = frames[web.id]!

        XCTAssertEqual(clockFrame.x, notesFrame.x)
        XCTAssertEqual(clockFrame.width, 300, "column takes its widest tile")
        XCTAssertEqual(notesFrame.width, 300)
        XCTAssertEqual(clockFrame.height, 150)
        XCTAssertEqual(notesFrame.minY, 160)
        XCTAssertEqual(notesFrame.height, 240, "the bottom tile is not stretched")
        XCTAssertEqual(webFrame.minX, clockFrame.maxX + 10)
        XCTAssertEqual(webFrame.height, 800)
    }

    func testTilesWithoutAHeightShareWhatIsLeft() {
        let column = UUID()
        let clock = item(300, 200, column: column), a = item(300, nil, column: column), b = item(300, nil, column: column)
        let frames = FlowLayout.layout([clock, a, b], in: canvas, options: options)
        // 800 - 200 - 2 gaps = 580, shared.
        XCTAssertEqual(frames[a.id]?.height, 290)
        XCTAssertEqual(frames[b.id]?.minY, 510)
        XCTAssertEqual(frames[b.id]?.maxY, 800)
    }

    func testAColumnThatHoldsTooMuchGivesWayInProportion() {
        let column = UUID()
        let a = item(300, 500, column: column), b = item(300, 400, column: column), c = item(300, nil, column: column)
        let heights = FlowLayout.heights(for: [a, b, c], available: 800, options: options)
        XCTAssertEqual(heights.reduce(0, +) + 20, 800, accuracy: 0.001)
        XCTAssertEqual(heights[2], 50, "a tile that fills keeps the shortest height")
        XCTAssertEqual(heights[0] / heights[1], 500.0 / 400.0, accuracy: 0.001)
    }

    func testColumnsAreRunsOfNeighbours() {
        let c1 = UUID(), c2 = UUID()
        let items = [item(200, 100, column: c1), item(200, 100, column: c1), item(200, nil, column: c2), item(200, 100, column: c1)]
        XCTAssertEqual(FlowLayout.columns(for: items).map(\.count), [2, 1, 1])
    }

    func testTooWideLayoutIsSqueezedToFit() {
        let items = (0..<4).map { _ in item(600, nil) }
        let frames = FlowLayout.layout(items, in: canvas, options: options)
        let rects = items.map { frames[$0.id]! }
        XCTAssertEqual(rects.first!.minX, 0, accuracy: 1)
        XCTAssertEqual(rects.last!.maxX, 1400, accuracy: 1)
        for (left, right) in zip(rects, rects.dropFirst()) {
            XCTAssertEqual(right.minX - left.maxX, 10, accuracy: 1)
        }
    }

    func testARowCanStartWhereItIsToldInsteadOfCentred() {
        let a = item(300, nil), b = item(300, nil)
        let frames = FlowLayout.layout([a, b], in: canvas, options: options, originX: 40)
        XCTAssertEqual(frames[a.id]?.minX, 40)
        // Never past the point where the row would run off the canvas.
        let late = FlowLayout.layout([a, b], in: canvas, options: options, originX: 1300)
        XCTAssertEqual(late[b.id]?.maxX, 1400)
    }

    /// Random boards: some tiles stacked, some with heights, some without.
    private func randomItems(_ generator: inout SeededGenerator, count: Int) -> [FlowLayout.Item] {
        var items: [FlowLayout.Item] = []
        for _ in 0..<count {
            let column = items.last.flatMap { Bool.random(using: &generator) ? $0.column : nil } ?? UUID()
            items.append(item(
                Double.random(in: 120...520, using: &generator).rounded(),
                Bool.random(using: &generator) ? nil : Double.random(in: 60...700, using: &generator).rounded(),
                column: column
            ))
        }
        return items
    }

    func testFramesNeverOverlapOrLeaveTheCanvas() {
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<200 {
            let count = Int.random(in: 1...9, using: &generator)
            let items = randomItems(&generator, count: count)
            let frames = FlowLayout.layout(items, in: canvas, options: options)
            XCTAssertEqual(frames.count, count)
            let rects = Array(frames.values)
            for rect in rects {
                XCTAssertGreaterThanOrEqual(rect.minX, -0.5)
                XCTAssertLessThanOrEqual(rect.maxX, canvas.width + 0.5)
                XCTAssertGreaterThanOrEqual(rect.minY, -0.5)
                XCTAssertLessThanOrEqual(rect.maxY, canvas.height + 0.5)
            }
            for i in rects.indices {
                for j in rects.indices where j > i {
                    XCTAssertEqual(rects[i].overlapArea(with: rects[j]), 0, "tiles overlap: \(rects[i]) \(rects[j])")
                }
            }
        }
    }

    func testReadingAnArrangementBackKeepsStacksTogether() {
        let column = UUID()
        let clock = item(280, 160, column: column), notes = item(300, nil, column: column), web = item(460, nil)
        let frames = FlowLayout.layout([clock, notes, web], in: canvas, options: options)
        let derived = FlowLayout.items(
            from: [web, notes, clock].map { ($0.id, frames[$0.id]!) },  // any input order
            canvasHeight: canvas.height, options: options
        )
        XCTAssertEqual(derived.map(\.id), [clock.id, notes.id, web.id])
        XCTAssertNil(derived[1].height, "the bottom tile reached the bottom, so it fills")
        XCTAssertNil(derived[2].height)
        XCTAssertEqual(FlowLayout.columns(for: derived).map(\.count), [2, 1])
        XCTAssertEqual(FlowLayout.layout(derived, in: canvas, options: options), frames)
    }

    /// Laying out, reading positions back and laying out again must not move anything.
    func testRoundTripThroughPositionsIsStable() {
        var generator = SeededGenerator(seed: 2026)
        for _ in 0..<300 {
            let items = randomItems(&generator, count: Int.random(in: 1...8, using: &generator))
            // A column that holds more than fits is squeezed below the
            // heights its tiles ask for, which cannot be read back exactly.
            let fits = FlowLayout.columns(for: items).allSatisfy { column in
                let asked = column.reduce(0) { $0 + max($1.height ?? options.minHeight, options.minHeight) }
                return asked + options.gap * Double(column.count - 1) <= canvas.height
            }
            guard fits else { continue }
            let frames = FlowLayout.layout(items, in: canvas, options: options)
            let derived = FlowLayout.items(
                from: items.map { ($0.id, frames[$0.id]!) },
                canvasHeight: canvas.height, options: options
            )
            let again = FlowLayout.layout(derived, in: canvas, options: options)
            XCTAssertEqual(again.count, frames.count)
            for (id, before) in frames {
                let after = again[id]!
                XCTAssertEqual(after.x, before.x, accuracy: 1.5, "x of \(before) became \(after)")
                XCTAssertEqual(after.y, before.y, accuracy: 1.5, "y of \(before) became \(after)")
                XCTAssertEqual(after.width, before.width, accuracy: 1.5)
                XCTAssertEqual(after.height, before.height, accuracy: 1.5)
            }
        }
    }

    // MARK: - Resizing

    func testATileCanGrowUntilItsColumnIsFull() {
        let column = UUID()
        let clock = item(300, 200, column: column), notes = item(300, nil, column: column), lone = item(300, 300)
        let items = [clock, notes, lone]
        // The note that fills gives way down to the shortest a tile is drawn.
        XCTAssertEqual(FlowLayout.maxHeight(of: clock.id, in: items, canvasHeight: 800, options: options), 740)
        XCTAssertEqual(FlowLayout.maxHeight(of: notes.id, in: items, canvasHeight: 800, options: options), 590)
        XCTAssertEqual(FlowLayout.maxHeight(of: lone.id, in: items, canvasHeight: 800, options: options), 800)
    }

    // MARK: - Dragging

    // Three full-height columns, 300 wide: a 240...540, b 550...850, m 860...1160.
    private func threeColumns() -> (a: FlowLayout.Item, b: FlowLayout.Item, m: FlowLayout.Item) {
        (item(300, nil), item(300, nil), item(300, nil))
    }

    private func drop(_ id: UUID, _ x: Double, _ y: Double, _ items: [FlowLayout.Item]) -> [FlowLayout.Item] {
        FlowLayout.dropping(id, at: LayoutPoint(x: x, y: y), items: items, in: canvas, options: options)
    }

    func testDroppingOnTheLowerHalfOfATileStacksUnderIt() {
        let (a, b, m) = threeColumns()
        let result = drop(m.id, 390, 600, [a, b, m])
        XCTAssertEqual(result.map(\.id), [a.id, m.id, b.id])
        XCTAssertEqual(result[1].column, a.column)
        XCTAssertEqual(FlowLayout.columns(for: result).map(\.count), [2, 1])
    }

    func testDroppingOnTheUpperHalfStacksAboveIt() {
        let (a, b, m) = threeColumns()
        let result = drop(m.id, 390, 100, [a, b, m])
        XCTAssertEqual(result.map(\.id), [m.id, a.id, b.id])
        XCTAssertEqual(result[0].column, a.column)
    }

    func testDroppingBelowTheLastTileOfAShortColumnStacksAtTheBottom() {
        let column = UUID()
        let top = item(300, 200, column: column), m = item(300, nil)
        // top is 0...200 in a column at 395...695; the space below it is free.
        let result = drop(m.id, 545, 600, [top, m])
        XCTAssertEqual(result.map(\.id), [top.id, m.id])
        XCTAssertEqual(result[1].column, column)
    }

    func testDroppingNearAColumnsEdgeMakesANewColumn() {
        let (a, b, m) = threeColumns()
        let before = drop(m.id, 250, 400, [a, b, m])
        XCTAssertEqual(before.map(\.id), [m.id, a.id, b.id])
        XCTAssertEqual(FlowLayout.columns(for: before).count, 3, "its own column, left of a")

        let farLeft = drop(m.id, 5, 400, [a, b, m])
        XCTAssertEqual(farLeft.map(\.id), [m.id, a.id, b.id])
        XCTAssertEqual(FlowLayout.columns(for: farLeft).count, 3)
    }

    func testOverItsOwnPlaceNothingChanges() {
        let (a, b, m) = threeColumns()
        let items = [a, b, m]
        XCTAssertEqual(drop(m.id, 1000, 400, items), items)
        XCTAssertEqual(drop(m.id, 845, 400, items), items, "right of b is where m already is")
        XCTAssertEqual(drop(m.id, 1390, 400, items), items, "past the end, where m already is")
    }

    func testLeavingAStackMakesAColumnOfItsOwn() {
        let column = UUID()
        let a = item(300, nil, column: column), m = item(300, nil, column: column), b = item(300, nil)
        let result = drop(m.id, 1350, 400, [a, m, b])
        XCTAssertEqual(result.map(\.id), [a.id, b.id, m.id])
        XCTAssertNotEqual(result[2].column, column)
        XCTAssertEqual(FlowLayout.columns(for: result).map(\.count), [1, 1, 1])
    }

    func testAStackedTileTakesTheColumnsWidth() {
        let a = item(420, nil), m = item(280, 160)
        // a is 345...765 (with m beside it); drop m on a's lower half.
        let result = drop(m.id, 555, 600, [a, m])
        XCTAssertEqual(result.last?.width, 420)
    }

    func testDroppingWithNothingElseOnTheBoardChangesNothing() {
        let m = item(300, nil)
        XCTAssertEqual(drop(m.id, 10, 10, [m]), [m])
    }
}

/// Deterministic randomness so a failing layout can be reproduced.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
