import XCTest
@testable import BlinkCore

final class ShortcutTests: XCTestCase {
    private typealias M = ModifierState

    func testDefaultShortcutIsTheFnKeyAlone() {
        XCTAssertEqual(Shortcut.default, Shortcut(keyCode: nil, modifiers: [ModifierKey(.function)]))
        XCTAssertEqual(Shortcut.default.displayString, "fn")
        XCTAssertTrue(Shortcut.default.isValid)
        XCTAssertTrue(Shortcut.default.isFunctionKeyAlone)
        XCTAssertTrue(Shortcut.default.requiresEventTap, "macOS shows fn only to apps allowed Input Monitoring")
    }

    func testTheAlternativeNeedsNoPermission() {
        XCTAssertFalse(Shortcut.withoutPermission.requiresEventTap)
        XCTAssertEqual(Shortcut.withoutPermission.carbonModifiers, 0x0800)
        XCTAssertEqual(Shortcut.withoutPermission.displayString, "⌥`")
        XCTAssertFalse(Shortcut.withoutPermission.isFunctionKeyAlone)
    }

    func testOnlyFnByItselfCountsAsTheFnKeyAlone() {
        XCTAssertFalse(Shortcut(keyCode: 49, modifiers: [ModifierKey(.function)]).isFunctionKeyAlone)
        XCTAssertFalse(Shortcut(keyCode: nil, modifiers: [ModifierKey(.function), ModifierKey(.shift)]).isFunctionKeyAlone)
        XCTAssertFalse(Shortcut(keyCode: nil, modifiers: [ModifierKey(.command, side: .right)]).isFunctionKeyAlone)
    }

    func testHoldingAndTappingTheDefaultShortcut() {
        let fn: UInt64 = 0x80_0000   // the fn flag, as the system reports it
        var tracker = ShortcutTracker(shortcut: .default)
        XCTAssertEqual(tracker.handle(.flagsChanged(rawFlags: fn)), .pressed)
        XCTAssertNil(tracker.handle(.flagsChanged(rawFlags: fn)), "the same flags again change nothing")
        XCTAssertEqual(tracker.handle(.flagsChanged(rawFlags: 0)), .released)

        // fn then an arrow is Home or End, not a peek.
        XCTAssertEqual(tracker.handle(.flagsChanged(rawFlags: fn)), .pressed)
        XCTAssertEqual(tracker.handle(.keyDown(keyCode: 123, rawFlags: fn, isRepeat: false)), .cancelled)
        XCTAssertNil(tracker.handle(.flagsChanged(rawFlags: 0)), "letting go afterwards is not a release")

        // An arrow key by itself reports the fn flag too, but only on the key.
        XCTAssertNil(tracker.handle(.keyDown(keyCode: 124, rawFlags: fn, isRepeat: false)))
        XCTAssertNil(tracker.handle(.keyUp(keyCode: 124, rawFlags: fn)))

        // fn with another modifier is some other shortcut.
        XCTAssertNil(tracker.handle(.flagsChanged(rawFlags: fn | 0x10_0000)))
    }

    func testSpecialShortcutsNeedTheEventTap() {
        XCTAssertTrue(Shortcut(keyCode: nil, modifiers: [ModifierKey(.command, side: .right)]).requiresEventTap)
        XCTAssertTrue(Shortcut(keyCode: nil, modifiers: [ModifierKey(.function)]).requiresEventTap)
        XCTAssertTrue(Shortcut(keyCode: 49, modifiers: [ModifierKey(.option, side: .left)]).requiresEventTap)
        XCTAssertFalse(Shortcut(keyCode: 105, modifiers: []).requiresEventTap)
        XCTAssertFalse(Shortcut(keyCode: 49, modifiers: [ModifierKey(.control), ModifierKey(.option)]).requiresEventTap)
    }

    func testCarbonModifierMask() {
        let all = Shortcut(keyCode: 0, modifiers: [
            ModifierKey(.command), ModifierKey(.shift), ModifierKey(.option), ModifierKey(.control),
        ])
        XCTAssertEqual(all.carbonModifiers, 0x0100 | 0x0200 | 0x0800 | 0x1000)
    }

    func testModifiersAreDeduplicatedAndOrdered() {
        let shortcut = Shortcut(keyCode: 49, modifiers: [
            ModifierKey(.command), ModifierKey(.control), ModifierKey(.command, side: .left),
        ])
        XCTAssertEqual(shortcut.modifiers.map(\.modifier), [.control, .command])
        XCTAssertEqual(shortcut.displayString, "⌃⌘Space")
    }

    func testDisplayStringSpellsOutSides() {
        XCTAssertEqual(Shortcut(keyCode: nil, modifiers: [ModifierKey(.command, side: .right)]).displayString, "Right ⌘")
        XCTAssertEqual(Shortcut(keyCode: nil, modifiers: [ModifierKey(.function)]).displayString, "fn")
        XCTAssertEqual(Shortcut(keyCode: 49, modifiers: [ModifierKey(.option, side: .left)]).displayString, "Left ⌥ Space")
    }

    func testModifierStateDecodesSides() {
        let state = M(rawFlags: M.commandMask | M.rightCommandMask | M.shiftMask | M.leftShiftMask)
        XCTAssertTrue(state.command.right)
        XCTAssertFalse(state.command.left)
        XCTAssertTrue(state.shift.left)
        XCTAssertFalse(state.option.down)
        XCTAssertFalse(state.isEmpty)
        XCTAssertTrue(M(rawFlags: 0x100).isEmpty)  // an unrelated bit
    }

    func testMatchingRequiresExactModifiers() {
        let shortcut = Shortcut(keyCode: 49, modifiers: [ModifierKey(.option)])
        XCTAssertTrue(shortcut.matchesModifiers(M(rawFlags: M.optionMask | M.leftOptionMask)))
        XCTAssertTrue(shortcut.matchesModifiers(M(rawFlags: M.optionMask | M.rightOptionMask)))
        XCTAssertFalse(shortcut.matchesModifiers(M(rawFlags: 0)))
        XCTAssertFalse(shortcut.matchesModifiers(M(rawFlags: M.optionMask | M.shiftMask)))
    }

    func testSideSpecificMatching() {
        let right = Shortcut(keyCode: nil, modifiers: [ModifierKey(.command, side: .right)])
        XCTAssertTrue(right.matchesModifiers(M(rawFlags: M.commandMask | M.rightCommandMask)))
        XCTAssertFalse(right.matchesModifiers(M(rawFlags: M.commandMask | M.leftCommandMask)))
        XCTAssertFalse(right.matchesModifiers(M(rawFlags: M.commandMask | M.leftCommandMask | M.rightCommandMask)))
    }

    func testFunctionFlagIsIgnoredForKeyShortcutsThatDoNotAskForIt() {
        // Arrow keys always carry the fn flag.
        let arrow = Shortcut(keyCode: 124, modifiers: [ModifierKey(.control)])
        XCTAssertTrue(arrow.matchesModifiers(M(rawFlags: M.controlMask | M.functionMask)))
        let fnOnly = Shortcut(keyCode: nil, modifiers: [ModifierKey(.function)])
        XCTAssertTrue(fnOnly.matchesModifiers(M(rawFlags: M.functionMask)))
        XCTAssertFalse(fnOnly.matchesModifiers(M(rawFlags: M.functionMask | M.shiftMask)))
        let rightOption = Shortcut(keyCode: nil, modifiers: [ModifierKey(.option, side: .right)])
        XCTAssertFalse(rightOption.matchesModifiers(M(rawFlags: M.optionMask | M.rightOptionMask | M.functionMask)))
    }

    func testShortcutRoundTripsThroughJSON() throws {
        let shortcut = Shortcut(keyCode: nil, modifiers: [ModifierKey(.option, side: .right)])
        let data = try JSONEncoder().encode(shortcut)
        XCTAssertEqual(try JSONDecoder().decode(Shortcut.self, from: data), shortcut)
    }

    // MARK: - Tracker

    func testModifierOnlyShortcutPressAndRelease() {
        var tracker = ShortcutTracker(shortcut: Shortcut(keyCode: nil, modifiers: [ModifierKey(.command, side: .right)]))
        XCTAssertEqual(tracker.handle(.flagsChanged(rawFlags: M.commandMask | M.rightCommandMask)), .pressed)
        XCTAssertNil(tracker.handle(.flagsChanged(rawFlags: M.commandMask | M.rightCommandMask)))
        XCTAssertEqual(tracker.handle(.flagsChanged(rawFlags: 0)), .released)
        XCTAssertNil(tracker.handle(.flagsChanged(rawFlags: 0)))
    }

    func testModifierOnlyShortcutIsCancelledByAnotherKey() {
        var tracker = ShortcutTracker(shortcut: Shortcut(keyCode: nil, modifiers: [ModifierKey(.command, side: .right)]))
        let flags = M.commandMask | M.rightCommandMask
        XCTAssertEqual(tracker.handle(.flagsChanged(rawFlags: flags)), .pressed)
        XCTAssertEqual(tracker.handle(.keyDown(keyCode: 8, rawFlags: flags, isRepeat: false)), .cancelled)
        // Letting go afterwards reports nothing further.
        XCTAssertNil(tracker.handle(.keyUp(keyCode: 8, rawFlags: flags)))
        XCTAssertNil(tracker.handle(.flagsChanged(rawFlags: 0)))
    }

    func testAddingAnotherModifierReleases() {
        var tracker = ShortcutTracker(shortcut: Shortcut(keyCode: nil, modifiers: [ModifierKey(.function)]))
        XCTAssertEqual(tracker.handle(.flagsChanged(rawFlags: M.functionMask)), .pressed)
        XCTAssertEqual(tracker.handle(.flagsChanged(rawFlags: M.functionMask | M.shiftMask | M.leftShiftMask)), .released)
    }

    func testKeyShortcutWithSideSpecificModifier() {
        var tracker = ShortcutTracker(shortcut: Shortcut(keyCode: 49, modifiers: [ModifierKey(.option, side: .right)]))
        let right = M.optionMask | M.rightOptionMask
        let left = M.optionMask | M.leftOptionMask
        XCTAssertNil(tracker.handle(.flagsChanged(rawFlags: right)))
        XCTAssertNil(tracker.handle(.keyDown(keyCode: 49, rawFlags: left, isRepeat: false)))
        XCTAssertEqual(tracker.handle(.keyDown(keyCode: 49, rawFlags: right, isRepeat: false)), .pressed)
        XCTAssertNil(tracker.handle(.keyDown(keyCode: 49, rawFlags: right, isRepeat: true)))
        XCTAssertEqual(tracker.handle(.keyUp(keyCode: 49, rawFlags: right)), .released)
    }

    func testKeyShortcutEndsWhenModifierIsReleasedFirst() {
        var tracker = ShortcutTracker(shortcut: Shortcut(keyCode: 49, modifiers: [ModifierKey(.option, side: .right)]))
        let right = M.optionMask | M.rightOptionMask
        XCTAssertEqual(tracker.handle(.keyDown(keyCode: 49, rawFlags: right, isRepeat: false)), .pressed)
        XCTAssertEqual(tracker.handle(.flagsChanged(rawFlags: 0)), .released)
        XCTAssertNil(tracker.handle(.keyUp(keyCode: 49, rawFlags: 0)))
    }

    func testRepeatedKeyDownDoesNotStartAHold() {
        var tracker = ShortcutTracker(shortcut: Shortcut(keyCode: 49, modifiers: [ModifierKey(.function)]))
        XCTAssertNil(tracker.handle(.keyDown(keyCode: 49, rawFlags: M.functionMask, isRepeat: true)))
        XCTAssertFalse(tracker.isActive)
    }
}
