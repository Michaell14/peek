import XCTest
@testable import BlickCore

final class PeekStateMachineTests: XCTestCase {
    func testHoldingShowsThenHidesOnRelease() {
        var machine = PeekStateMachine(tapThreshold: 0.3)
        XCTAssertEqual(machine.handle(.shortcutDown(at: 10)), [.show])
        XCTAssertTrue(machine.isVisible)
        XCTAssertEqual(machine.handle(.shortcutUp(at: 11)), [.hide])
        XCTAssertEqual(machine.state, .hidden)
    }

    func testTapPinsTheOverlay() {
        var machine = PeekStateMachine(tapThreshold: 0.3)
        XCTAssertEqual(machine.handle(.shortcutDown(at: 10)), [.show])
        XCTAssertEqual(machine.handle(.shortcutUp(at: 10.15)), [.makeInteractive])
        XCTAssertTrue(machine.isPinned)
    }

    func testPressingAgainWhilePinnedHidesOnceAndIgnoresTheRelease() {
        var machine = PeekStateMachine(tapThreshold: 0.3)
        _ = machine.handle(.shortcutDown(at: 0))
        _ = machine.handle(.shortcutUp(at: 0.1))
        XCTAssertEqual(machine.handle(.shortcutDown(at: 5)), [.hide])
        XCTAssertFalse(machine.isVisible)
        // Releasing that same press must not reopen or re-hide anything.
        XCTAssertEqual(machine.handle(.shortcutUp(at: 5.05)), [])
        XCTAssertEqual(machine.state, .hidden)
    }

    func testKeyRepeatWhileHoldingIsIgnored() {
        var machine = PeekStateMachine()
        _ = machine.handle(.shortcutDown(at: 0))
        XCTAssertEqual(machine.handle(.shortcutDown(at: 0.5)), [])
        XCTAssertEqual(machine.handle(.shortcutDown(at: 0.6)), [])
        // The hold is timed from the first press, so this is not a tap.
        XCTAssertEqual(machine.handle(.shortcutUp(at: 0.7)), [.hide])
    }

    func testDismissWhileHoldingWaitsForRelease() {
        var machine = PeekStateMachine()
        _ = machine.handle(.shortcutDown(at: 0))
        XCTAssertEqual(machine.handle(.dismiss), [.hide])
        XCTAssertEqual(machine.state, .releasing)
        XCTAssertEqual(machine.handle(.shortcutUp(at: 2)), [])
        XCTAssertEqual(machine.state, .hidden)
    }

    func testCancelledShortcutHidesWithoutPinning() {
        var machine = PeekStateMachine(tapThreshold: 0.3)
        _ = machine.handle(.shortcutDown(at: 0))
        // Cancelled almost immediately: must not be mistaken for a tap.
        XCTAssertEqual(machine.handle(.shortcutCancelled), [.hide])
        XCTAssertEqual(machine.handle(.shortcutUp(at: 0.05)), [])
        XCTAssertEqual(machine.state, .hidden)
    }

    func testPinFromHiddenShowsInteractive() {
        var machine = PeekStateMachine()
        XCTAssertEqual(machine.handle(.pin), [.show, .makeInteractive])
        XCTAssertEqual(machine.handle(.dismiss), [.hide])
        XCTAssertEqual(machine.state, .hidden)
    }

    func testPinWhileHoldingSurvivesTheRelease() {
        var machine = PeekStateMachine()
        _ = machine.handle(.shortcutDown(at: 0))
        XCTAssertEqual(machine.handle(.pin), [.makeInteractive])
        XCTAssertEqual(machine.handle(.shortcutUp(at: 3)), [])
        XCTAssertTrue(machine.isPinned)
    }

    func testMissedKeyUpRecoversOnNextPress() {
        var machine = PeekStateMachine()
        _ = machine.handle(.pin)
        XCTAssertEqual(machine.handle(.shortcutDown(at: 1)), [.hide])
        // The key-up never arrives; the next press still opens the overlay.
        XCTAssertEqual(machine.handle(.shortcutDown(at: 9)), [.show])
        XCTAssertEqual(machine.handle(.shortcutUp(at: 12)), [.hide])
    }

    func testStrayEventsWhenHiddenDoNothing() {
        var machine = PeekStateMachine()
        XCTAssertEqual(machine.handle(.shortcutUp(at: 1)), [])
        XCTAssertEqual(machine.handle(.dismiss), [])
        XCTAssertEqual(machine.handle(.shortcutCancelled), [])
        XCTAssertEqual(machine.state, .hidden)
    }

    func testTapThresholdBoundary() {
        var machine = PeekStateMachine(tapThreshold: 0.3)
        _ = machine.handle(.shortcutDown(at: 0))
        XCTAssertEqual(machine.handle(.shortcutUp(at: 0.3)), [.makeInteractive])
        _ = machine.handle(.dismiss)
        _ = machine.handle(.shortcutDown(at: 1))
        XCTAssertEqual(machine.handle(.shortcutUp(at: 1.31)), [.hide])
    }
}
