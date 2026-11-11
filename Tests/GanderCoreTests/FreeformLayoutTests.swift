import XCTest
@testable import GanderCore

final class FreeformLayoutTests: XCTestCase {
    private let canvas = Size(width: 1000, height: 600)
    private let noSnap = SnapOptions(isEnabled: false)

    func testMoveWithoutSnapping() {
        let result = FreeformLayout.move(
            Rect(x: 100, y: 100, width: 200, height: 150),
            by: Point(x: 33, y: -17), in: canvas, others: [], snap: noSnap
        )
        XCTAssertEqual(result.rect, Rect(x: 133, y: 83, width: 200, height: 150))
        XCTAssertTrue(result.guides.isEmpty)
    }

    func testMoveIsClampedToTheCanvas() {
        let rect = Rect(x: 100, y: 100, width: 200, height: 150)
        XCTAssertEqual(
            FreeformLayout.move(rect, by: Point(x: -500, y: -500), in: canvas, others: [], snap: noSnap).rect.origin,
            Point(x: 0, y: 0)
        )
        XCTAssertEqual(
            FreeformLayout.move(rect, by: Point(x: 5000, y: 5000), in: canvas, others: [], snap: noSnap).rect.origin,
            Point(x: 800, y: 450)
        )
    }

    func testMoveSnapsToCanvasEdgeAndCentre() {
        let rect = Rect(x: 100, y: 100, width: 200, height: 150)
        let toEdge = FreeformLayout.move(rect, by: Point(x: -95, y: 0), in: canvas, others: [])
        XCTAssertEqual(toEdge.rect.x, 0)
        XCTAssertTrue(toEdge.guides.contains(Guide(axis: .vertical, position: 0)))

        // Centre of the tile (x + 100) lands 4pt from the canvas centre.
        let toCentre = FreeformLayout.move(rect, by: Point(x: 296, y: 0), in: canvas, others: [])
        XCTAssertEqual(toCentre.rect.midX, 500)
        XCTAssertTrue(toCentre.guides.contains(Guide(axis: .vertical, position: 500)))
    }

    func testMoveSnapsBesideANeighbourLeavingAGap() {
        let neighbour = Rect(x: 400, y: 50, width: 200, height: 300)
        let rect = Rect(x: 50, y: 50, width: 200, height: 300)
        // Right edge would land at 393; one gap (12) before the neighbour is 388.
        let result = FreeformLayout.move(rect, by: Point(x: 143, y: 0), in: canvas, others: [neighbour])
        XCTAssertEqual(result.rect.maxX, 388)
        // Same top edge as the neighbour, so a horizontal guide appears too.
        XCTAssertTrue(result.guides.contains(Guide(axis: .horizontal, position: 50)))
    }

    func testMoveDoesNotSnapBeyondThreshold() {
        let rect = Rect(x: 100, y: 100, width: 200, height: 150)
        let result = FreeformLayout.move(rect, by: Point(x: -80, y: 0), in: canvas, others: [])
        XCTAssertEqual(result.rect.x, 20)
    }

    func testResizeFromEachSide() {
        let rect = Rect(x: 200, y: 200, width: 300, height: 200)
        let right = FreeformLayout.resize(rect, handle: .right, by: Point(x: 50, y: 99), in: canvas, others: [], snap: noSnap).rect
        XCTAssertEqual(right, Rect(x: 200, y: 200, width: 350, height: 200))
        let topLeft = FreeformLayout.resize(rect, handle: .topLeft, by: Point(x: -40, y: -30), in: canvas, others: [], snap: noSnap).rect
        XCTAssertEqual(topLeft, Rect(x: 160, y: 170, width: 340, height: 230))
        let bottom = FreeformLayout.resize(rect, handle: .bottom, by: Point(x: 77, y: 60), in: canvas, others: [], snap: noSnap).rect
        XCTAssertEqual(bottom, Rect(x: 200, y: 200, width: 300, height: 260))
    }

    func testResizeRespectsMinimumSizeAndKeepsTheOppositeEdge() {
        let rect = Rect(x: 200, y: 200, width: 300, height: 200)
        let min = Size(width: 160, height: 100)
        let shrunk = FreeformLayout.resize(rect, handle: .left, by: Point(x: 900, y: 0), in: canvas, others: [], snap: noSnap, minSize: min).rect
        XCTAssertEqual(shrunk.maxX, 500)
        XCTAssertEqual(shrunk.width, 160)
        let squashed = FreeformLayout.resize(rect, handle: .bottom, by: Point(x: 0, y: -900), in: canvas, others: [], snap: noSnap, minSize: min).rect
        XCTAssertEqual(squashed.minY, 200)
        XCTAssertEqual(squashed.height, 100)
    }

    func testResizeStopsAtTheCanvasEdge() {
        let rect = Rect(x: 200, y: 200, width: 300, height: 200)
        let grown = FreeformLayout.resize(rect, handle: .bottomRight, by: Point(x: 9000, y: 9000), in: canvas, others: [], snap: noSnap).rect
        XCTAssertEqual(grown.maxX, 1000)
        XCTAssertEqual(grown.maxY, 600)
        let up = FreeformLayout.resize(rect, handle: .topLeft, by: Point(x: -9000, y: -9000), in: canvas, others: [], snap: noSnap).rect
        XCTAssertEqual(up.origin, .zero)
    }

    func testResizeSnapsMovingEdgeToNeighbour() {
        let neighbour = Rect(x: 600, y: 0, width: 200, height: 600)
        let rect = Rect(x: 100, y: 100, width: 300, height: 200)
        let result = FreeformLayout.resize(rect, handle: .right, by: Point(x: 185, y: 0), in: canvas, others: [neighbour])
        XCTAssertEqual(result.rect.maxX, 588, "snaps one gap before the neighbour")
        XCTAssertEqual(result.rect.minX, 100)
    }

    func testClampShrinksOversizedRects() {
        let rect = FreeformLayout.clamp(Rect(x: -50, y: 700, width: 4000, height: 100), to: canvas)
        XCTAssertEqual(rect, Rect(x: 0, y: 500, width: 1000, height: 100))
    }

    func testPlaceNewOnEmptyCanvas() {
        let rect = FreeformLayout.placeNew(size: Size(width: 300, height: 200), in: canvas, existing: [])
        XCTAssertEqual(rect, Rect(x: 0, y: 0, width: 300, height: 200))
    }

    func testPlaceNewAvoidsExistingTiles() {
        let existing = [Rect(x: 0, y: 0, width: 400, height: 600)]
        let rect = FreeformLayout.placeNew(size: Size(width: 300, height: 200), in: canvas, existing: existing, gap: 12)
        XCTAssertGreaterThanOrEqual(rect.minX, 412)
        XCTAssertEqual(rect.overlapArea(with: existing[0]), 0)
        XCTAssertLessThanOrEqual(rect.maxX, canvas.width)
    }

    func testPlaceNewOnAFullCanvasPicksTheLeastCrowdedSpot() {
        let existing = [Rect(x: 0, y: 0, width: 1000, height: 500)]
        let rect = FreeformLayout.placeNew(size: Size(width: 300, height: 200), in: canvas, existing: existing)
        XCTAssertEqual(rect.maxY, 600, accuracy: 24)
        XCTAssertLessThanOrEqual(rect.maxX, canvas.width)
    }

    func testPlaceNewShrinksTilesLargerThanTheCanvas() {
        let rect = FreeformLayout.placeNew(size: Size(width: 5000, height: 5000), in: canvas, existing: [])
        XCTAssertEqual(rect.size, canvas)
    }

    func testGeometryRoundTripThroughUnitSpace() {
        let rect = Rect(x: 250, y: 150, width: 500, height: 300)
        let unit = rect.normalized(in: canvas)
        XCTAssertEqual(unit, Rect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        XCTAssertEqual(unit.scaled(to: canvas), rect)
        XCTAssertEqual(rect.normalized(in: .zero), .zero)
    }

    func testDistanceAndContains() {
        let rect = Rect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertEqual(rect.distance(to: Point(x: 5, y: 5)), 0)
        XCTAssertEqual(rect.distance(to: Point(x: 13, y: 14)), 5)
        XCTAssertTrue(rect.contains(Point(x: 0, y: 0)))
        XCTAssertFalse(rect.contains(Point(x: 10, y: 10)))
    }
}
