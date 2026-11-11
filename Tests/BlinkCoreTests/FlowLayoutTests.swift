import XCTest
@testable import BlinkCore

final class FlowLayoutTests: XCTestCase {
    private let canvas = LayoutSize(width: 1400, height: 800)
    private let options = FlowLayout.Options(gap: 10, minWidth: 100, minHeight: 50)

    private func item(_ width: Double, _ height: Double?) -> FlowLayout.Item {
        FlowLayout.Item(id: UUID(), width: width, height: height)
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

    func testShortTilesStackAndTheLastOneFillsTheColumn() {
        let clock = item(280, 150), notes = item(300, 240), web = item(400, nil)
        let frames = FlowLayout.layout([clock, notes, web], in: canvas, options: options)
        let clockFrame = frames[clock.id]!, notesFrame = frames[notes.id]!, webFrame = frames[web.id]!

        XCTAssertEqual(clockFrame.x, notesFrame.x)
        XCTAssertEqual(clockFrame.width, 300, "column takes its widest tile")
        XCTAssertEqual(notesFrame.width, 300)
        XCTAssertEqual(clockFrame.height, 150)
        XCTAssertEqual(notesFrame.minY, 160)
        XCTAssertEqual(notesFrame.maxY, 800, "last tile reaches the bottom")
        XCTAssertEqual(webFrame.minX, clockFrame.maxX + 10)
        XCTAssertEqual(webFrame.height, 800)
    }

    func testColumnBreaksWhenHeightRunsOut() {
        let items = [item(200, 500), item(200, 400), item(200, 100)]
        let columns = FlowLayout.columns(for: items, availableHeight: 800, options: options)
        XCTAssertEqual(columns.map(\.count), [1, 2])
    }

    func testFillTileNeverSharesAColumn() {
        let items = [item(200, 100), item(200, nil), item(200, 100), item(200, 100)]
        let columns = FlowLayout.columns(for: items, availableHeight: 800, options: options)
        XCTAssertEqual(columns.map(\.count), [1, 1, 2])
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

    func testFramesNeverOverlapOrLeaveTheCanvas() {
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<200 {
            let count = Int.random(in: 1...9, using: &generator)
            let items = (0..<count).map { _ in
                item(Double.random(in: 80...700, using: &generator),
                     Bool.random(using: &generator) ? nil : Double.random(in: 40...900, using: &generator))
            }
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
        let clock = item(280, 160), notes = item(300, 240), web = item(460, nil)
        let frames = FlowLayout.layout([clock, notes, web], in: canvas, options: options)
        let derived = FlowLayout.items(
            from: [web, notes, clock].map { ($0.id, frames[$0.id]!) },  // any input order
            canvasHeight: canvas.height, options: options
        )
        XCTAssertEqual(derived.map(\.id), [clock.id, notes.id, web.id])
        XCTAssertNil(derived[2].height, "a tall tile on its own fills its column")
        XCTAssertEqual(FlowLayout.columns(for: derived, availableHeight: canvas.height, options: options).map(\.count), [2, 1])
        XCTAssertEqual(FlowLayout.layout(derived, in: canvas, options: options), frames)
    }

    /// Flow -> freeform -> flow must not move anything.
    func testRoundTripThroughPositionsIsStable() {
        var generator = SeededGenerator(seed: 2026)
        for _ in 0..<300 {
            let count = Int.random(in: 1...8, using: &generator)
            let items = (0..<count).map { _ in
                item(Double.random(in: 120...520, using: &generator).rounded(),
                     Bool.random(using: &generator) ? nil : Double.random(in: 60...700, using: &generator).rounded())
            }
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

    func testInsertionIndexBetweenColumns() {
        let a = item(300, nil), b = item(300, nil), moving = item(300, nil)
        let items = [a, b, moving]
        // With the moving tile removed: a = 395...695, b = 705...1005.
        XCTAssertEqual(FlowLayout.insertionIndex(at: LayoutPoint(x: 400, y: 400), moving: moving.id, items: items, in: canvas, options: options), 0)
        XCTAssertEqual(FlowLayout.insertionIndex(at: LayoutPoint(x: 690, y: 400), moving: moving.id, items: items, in: canvas, options: options), 1)
        XCTAssertEqual(FlowLayout.insertionIndex(at: LayoutPoint(x: 1300, y: 400), moving: moving.id, items: items, in: canvas, options: options), 2)
        XCTAssertEqual(FlowLayout.insertionIndex(at: LayoutPoint(x: 10, y: 10), moving: moving.id, items: items, in: canvas, options: options), 0)
    }

    func testInsertionIndexWithinAStack() {
        let top = item(300, 200), bottom = item(300, 200), moving = item(300, nil)
        let items = [top, bottom, moving]
        // The stack is centred: x 550...850, top 0...200, bottom 210...800.
        XCTAssertEqual(FlowLayout.insertionIndex(at: LayoutPoint(x: 700, y: 50), moving: moving.id, items: items, in: canvas, options: options), 0)
        XCTAssertEqual(FlowLayout.insertionIndex(at: LayoutPoint(x: 700, y: 150), moving: moving.id, items: items, in: canvas, options: options), 1)
        XCTAssertEqual(FlowLayout.insertionIndex(at: LayoutPoint(x: 700, y: 700), moving: moving.id, items: items, in: canvas, options: options), 2)
    }

    func testInsertionIndexWithNothingElseOnTheBoard() {
        let moving = item(300, nil)
        XCTAssertEqual(FlowLayout.insertionIndex(at: .zero, moving: moving.id, items: [moving], in: canvas, options: options), 0)
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
