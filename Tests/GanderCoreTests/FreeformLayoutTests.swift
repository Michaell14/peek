import XCTest
@testable import GanderCore

final class FreeformLayoutTests: XCTestCase {
    private let canvas = LayoutSize(width: 1000, height: 600)
    private let noSnap = SnapOptions(isEnabled: false)

    func testMoveWithoutSnapping() {
        let result = FreeformLayout.move(
            LayoutRect(x: 100, y: 100, width: 200, height: 150),
            by: LayoutPoint(x: 33, y: -17), in: canvas, others: [], snap: noSnap
        )
        XCTAssertEqual(result.rect, LayoutRect(x: 133, y: 83, width: 200, height: 150))
        XCTAssertTrue(result.guides.isEmpty)
    }

    func testMoveIsClampedToTheCanvas() {
        let rect = LayoutRect(x: 100, y: 100, width: 200, height: 150)
        XCTAssertEqual(
            FreeformLayout.move(rect, by: LayoutPoint(x: -500, y: -500), in: canvas, others: [], snap: noSnap).rect.origin,
            LayoutPoint(x: 0, y: 0)
        )
        XCTAssertEqual(
            FreeformLayout.move(rect, by: LayoutPoint(x: 5000, y: 5000), in: canvas, others: [], snap: noSnap).rect.origin,
            LayoutPoint(x: 800, y: 450)
        )
    }

    func testMoveSnapsToCanvasEdgeAndCentre() {
        let rect = LayoutRect(x: 100, y: 100, width: 200, height: 150)
        let toEdge = FreeformLayout.move(rect, by: LayoutPoint(x: -95, y: 0), in: canvas, others: [])
        XCTAssertEqual(toEdge.rect.x, 0)
        XCTAssertTrue(toEdge.guides.contains(SnapGuide(axis: .vertical, position: 0)))

        // Centre of the tile (x + 100) lands 4pt from the canvas centre.
        let toCentre = FreeformLayout.move(rect, by: LayoutPoint(x: 296, y: 0), in: canvas, others: [])
        XCTAssertEqual(toCentre.rect.midX, 500)
        XCTAssertTrue(toCentre.guides.contains(SnapGuide(axis: .vertical, position: 500)))
    }

    func testMoveSnapsBesideANeighbourLeavingAGap() {
        let neighbour = LayoutRect(x: 400, y: 50, width: 200, height: 300)
        let rect = LayoutRect(x: 50, y: 50, width: 200, height: 300)
        // Right edge would land at 393; one gap (12) before the neighbour is 388.
        let result = FreeformLayout.move(rect, by: LayoutPoint(x: 143, y: 0), in: canvas, others: [neighbour])
        XCTAssertEqual(result.rect.maxX, 388)
        // Same top edge as the neighbour, so a horizontal guide appears too.
        XCTAssertTrue(result.guides.contains(SnapGuide(axis: .horizontal, position: 50)))
    }

    func testMoveDoesNotSnapBeyondThreshold() {
        let rect = LayoutRect(x: 100, y: 100, width: 200, height: 150)
        let result = FreeformLayout.move(rect, by: LayoutPoint(x: -80, y: 0), in: canvas, others: [])
        XCTAssertEqual(result.rect.x, 20)
    }

    func testResizeFromEachSide() {
        let rect = LayoutRect(x: 200, y: 200, width: 300, height: 200)
        let right = FreeformLayout.resize(rect, handle: .right, by: LayoutPoint(x: 50, y: 99), in: canvas, others: [], snap: noSnap).rect
        XCTAssertEqual(right, LayoutRect(x: 200, y: 200, width: 350, height: 200))
        let topLeft = FreeformLayout.resize(rect, handle: .topLeft, by: LayoutPoint(x: -40, y: -30), in: canvas, others: [], snap: noSnap).rect
        XCTAssertEqual(topLeft, LayoutRect(x: 160, y: 170, width: 340, height: 230))
        let bottom = FreeformLayout.resize(rect, handle: .bottom, by: LayoutPoint(x: 77, y: 60), in: canvas, others: [], snap: noSnap).rect
        XCTAssertEqual(bottom, LayoutRect(x: 200, y: 200, width: 300, height: 260))
    }

    func testResizeRespectsMinimumSizeAndKeepsTheOppositeEdge() {
        let rect = LayoutRect(x: 200, y: 200, width: 300, height: 200)
        let min = LayoutSize(width: 160, height: 100)
        let shrunk = FreeformLayout.resize(rect, handle: .left, by: LayoutPoint(x: 900, y: 0), in: canvas, others: [], snap: noSnap, minSize: min).rect
        XCTAssertEqual(shrunk.maxX, 500)
        XCTAssertEqual(shrunk.width, 160)
        let squashed = FreeformLayout.resize(rect, handle: .bottom, by: LayoutPoint(x: 0, y: -900), in: canvas, others: [], snap: noSnap, minSize: min).rect
        XCTAssertEqual(squashed.minY, 200)
        XCTAssertEqual(squashed.height, 100)
    }

    func testResizeStopsAtTheCanvasEdge() {
        let rect = LayoutRect(x: 200, y: 200, width: 300, height: 200)
        let grown = FreeformLayout.resize(rect, handle: .bottomRight, by: LayoutPoint(x: 9000, y: 9000), in: canvas, others: [], snap: noSnap).rect
        XCTAssertEqual(grown.maxX, 1000)
        XCTAssertEqual(grown.maxY, 600)
        let up = FreeformLayout.resize(rect, handle: .topLeft, by: LayoutPoint(x: -9000, y: -9000), in: canvas, others: [], snap: noSnap).rect
        XCTAssertEqual(up.origin, .zero)
    }

    func testResizeSnapsMovingEdgeToNeighbour() {
        let neighbour = LayoutRect(x: 600, y: 0, width: 200, height: 600)
        let rect = LayoutRect(x: 100, y: 100, width: 300, height: 200)
        let result = FreeformLayout.resize(rect, handle: .right, by: LayoutPoint(x: 185, y: 0), in: canvas, others: [neighbour])
        XCTAssertEqual(result.rect.maxX, 588, "snaps one gap before the neighbour")
        XCTAssertEqual(result.rect.minX, 100)
    }

    func testClampShrinksOversizedRects() {
        let rect = FreeformLayout.clamp(LayoutRect(x: -50, y: 700, width: 4000, height: 100), to: canvas)
        XCTAssertEqual(rect, LayoutRect(x: 0, y: 500, width: 1000, height: 100))
    }

    func testPlaceNewOnEmptyCanvas() {
        let rect = FreeformLayout.placeNew(size: LayoutSize(width: 300, height: 200), in: canvas, existing: [])
        XCTAssertEqual(rect, LayoutRect(x: 0, y: 0, width: 300, height: 200))
    }

    func testPlaceNewAvoidsExistingTiles() {
        let existing = [LayoutRect(x: 0, y: 0, width: 400, height: 600)]
        let rect = FreeformLayout.placeNew(size: LayoutSize(width: 300, height: 200), in: canvas, existing: existing, gap: 12)
        XCTAssertGreaterThanOrEqual(rect.minX, 412)
        XCTAssertEqual(rect.overlapArea(with: existing[0]), 0)
        XCTAssertLessThanOrEqual(rect.maxX, canvas.width)
    }

    func testPlaceNewOnAFullCanvasPicksTheLeastCrowdedSpot() {
        let existing = [LayoutRect(x: 0, y: 0, width: 1000, height: 500)]
        let rect = FreeformLayout.placeNew(size: LayoutSize(width: 300, height: 200), in: canvas, existing: existing)
        XCTAssertEqual(rect.maxY, 600, accuracy: 24)
        XCTAssertLessThanOrEqual(rect.maxX, canvas.width)
    }

    func testPlaceNewShrinksTilesLargerThanTheCanvas() {
        let rect = FreeformLayout.placeNew(size: LayoutSize(width: 5000, height: 5000), in: canvas, existing: [])
        XCTAssertEqual(rect.size, canvas)
    }

    func testGeometryRoundTripThroughUnitSpace() {
        let rect = LayoutRect(x: 250, y: 150, width: 500, height: 300)
        let unit = rect.normalized(in: canvas)
        XCTAssertEqual(unit, LayoutRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        XCTAssertEqual(unit.scaled(to: canvas), rect)
        XCTAssertEqual(rect.normalized(in: .zero), .zero)
    }

    func testDistanceAndContains() {
        let rect = LayoutRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertEqual(rect.distance(to: LayoutPoint(x: 5, y: 5)), 0)
        XCTAssertEqual(rect.distance(to: LayoutPoint(x: 13, y: 14)), 5)
        XCTAssertTrue(rect.contains(LayoutPoint(x: 0, y: 0)))
        XCTAssertFalse(rect.contains(LayoutPoint(x: 10, y: 10)))
    }
}
