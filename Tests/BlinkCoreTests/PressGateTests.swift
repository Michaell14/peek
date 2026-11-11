import XCTest
@testable import BlinkCore

final class PressGateTests: XCTestCase {
    func testAHoldIsPassedOnOnceThePauseIsOver() {
        var gate = PressGate(delay: 0.12)
        XCTAssertEqual(gate.pressed(at: 10), [])
        XCTAssertTrue(gate.isPending)
        XCTAssertEqual(gate.timerFired(at: 10.12).map(rounded), [.down(heldFor: 0.12)])
        XCTAssertFalse(gate.isPending)
        XCTAssertEqual(gate.released(at: 11), [.up])
    }

    func testAnotherKeyInsideThePauseMeansNothingHappened() {
        var gate = PressGate(delay: 0.12)
        XCTAssertEqual(gate.pressed(at: 10), [])
        XCTAssertEqual(gate.cancelled(), [], "fn then an arrow never reaches the overlay")
        XCTAssertFalse(gate.isPending)
        XCTAssertEqual(gate.timerFired(at: 10.12), [], "a timer that was already on its way")
        XCTAssertEqual(gate.released(at: 10.3), [])
    }

    func testAQuickTapIsNotLost() {
        var gate = PressGate(delay: 0.12)
        XCTAssertEqual(gate.pressed(at: 10), [])
        XCTAssertEqual(gate.released(at: 10.05).map(rounded), [.down(heldFor: 0.05), .up])
        XCTAssertEqual(gate.timerFired(at: 10.12), [])
    }

    func testAnotherKeyAfterThePauseCancelsTheHold() {
        var gate = PressGate(delay: 0.12)
        _ = gate.pressed(at: 10)
        _ = gate.timerFired(at: 10.12)
        XCTAssertEqual(gate.cancelled(), [.cancel])
        XCTAssertEqual(gate.released(at: 10.5), [], "the release that follows belongs to the other combo")
    }

    func testWithNoDelayEverythingGoesStraightThrough() {
        var gate = PressGate(delay: 0)
        XCTAssertEqual(gate.pressed(at: 3), [.down(heldFor: 0)])
        XCTAssertFalse(gate.isPending)
        XCTAssertEqual(gate.cancelled(), [.cancel])
        XCTAssertEqual(gate.pressed(at: 4), [.down(heldFor: 0)])
        XCTAssertEqual(gate.released(at: 5), [.up])
    }

    func testStrayEventsAreIgnored() {
        var gate = PressGate(delay: 0.12)
        XCTAssertEqual(gate.released(at: 1), [])
        XCTAssertEqual(gate.cancelled(), [])
        XCTAssertEqual(gate.timerFired(at: 1), [])

        _ = gate.pressed(at: 2)
        XCTAssertEqual(gate.pressed(at: 2.01), [], "a second press while the first is pending")
        _ = gate.timerFired(at: 2.12)
        XCTAssertEqual(gate.pressed(at: 2.2), [], "or while it is down")
        XCTAssertEqual(gate.released(at: 3), [.up])
    }

    func testResetForgetsAPressInProgress() {
        var gate = PressGate(delay: 0.12)
        _ = gate.pressed(at: 1)
        gate.reset()
        XCTAssertFalse(gate.isPending)
        XCTAssertEqual(gate.released(at: 2), [])

        _ = gate.pressed(at: 3)
        _ = gate.timerFired(at: 3.12)
        gate.reset()
        XCTAssertEqual(gate.released(at: 4), [])
    }

    func testANegativeDelayIsNoDelay() {
        var gate = PressGate(delay: -1)
        XCTAssertEqual(gate.delay, 0)
        XCTAssertEqual(gate.pressed(at: 1), [.down(heldFor: 0)])
    }

    /// Rounds the time away so that 10.12 - 10 compares equal to 0.12.
    private func rounded(_ action: PressGate.Action) -> PressGate.Action {
        if case .down(let held) = action {
            return .down(heldFor: (held * 1000).rounded() / 1000)
        }
        return action
    }
}
