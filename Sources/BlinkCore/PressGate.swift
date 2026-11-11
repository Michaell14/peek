import Foundation

/// Holds back the first moment of a press on a shortcut made of modifier keys
/// alone.
///
/// fn is also how you reach Home, End and forward delete; right ⌘ is also the
/// start of ⌘C. Without a pause, every one of those would flash the overlay
/// before the second key cancelled it. The gate waits `delay` seconds before
/// passing a press on, and says nothing at all if another key arrives first.
/// A quick tap is not lost: letting go inside the pause passes on the press
/// and the release together.
public struct PressGate: Sendable {
    public enum Action: Equatable, Sendable {
        /// The shortcut is down, and has been for `heldFor` seconds already.
        case down(heldFor: TimeInterval)
        case up
        /// A press that was passed on turned out to belong to another combo.
        case cancel
    }

    public let delay: TimeInterval
    private var pendingSince: TimeInterval?
    private var isDown = false

    /// A delay of zero passes everything straight through.
    public init(delay: TimeInterval) {
        self.delay = max(delay, 0)
    }

    /// True while a press is being held back. The caller should arrange for
    /// `timerFired` to be called once `delay` has gone by.
    public var isPending: Bool { pendingSince != nil }

    public mutating func pressed(at time: TimeInterval) -> [Action] {
        guard !isDown, pendingSince == nil else { return [] }
        if delay == 0 {
            isDown = true
            return [.down(heldFor: 0)]
        }
        pendingSince = time
        return []
    }

    public mutating func released(at time: TimeInterval) -> [Action] {
        if let since = pendingSince {
            pendingSince = nil
            return [.down(heldFor: max(time - since, 0)), .up]
        }
        guard isDown else { return [] }
        isDown = false
        return [.up]
    }

    public mutating func cancelled() -> [Action] {
        if pendingSince != nil {
            pendingSince = nil
            return []
        }
        guard isDown else { return [] }
        isDown = false
        return [.cancel]
    }

    public mutating func timerFired(at time: TimeInterval) -> [Action] {
        guard let since = pendingSince else { return [] }
        pendingSince = nil
        isDown = true
        return [.down(heldFor: max(time - since, 0))]
    }

    /// Forgets a press in progress, for when listening stops.
    public mutating func reset() {
        pendingSince = nil
        isDown = false
    }
}
