import Foundation

/// Decides what the overlay does as the shortcut goes down and up.
///
/// Hold the shortcut and the overlay stays up only while it is held. Tap it
/// (press and release quickly) and the overlay stays open and becomes
/// interactive until it is dismissed.
public struct PeekStateMachine: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case hidden
        /// Visible because the shortcut is physically held.
        case holding(since: Double)
        /// Visible and interactive; stays until dismissed.
        case pinned
        /// Hidden, but the shortcut is still held from the press that hid it.
        case releasing
    }

    public enum Event: Hashable, Sendable {
        case shortcutDown(at: Double)
        case shortcutUp(at: Double)
        /// The key press turned out to belong to something else.
        case shortcutCancelled
        /// Open and keep open, e.g. from the menu bar.
        case pin
        /// Escape, a click on the backdrop, or the menu bar item.
        case dismiss
    }

    public enum Effect: Hashable, Sendable {
        case show
        case makeInteractive
        case hide
    }

    public private(set) var state: State = .hidden
    /// A press shorter than this many seconds counts as a tap.
    public var tapThreshold: Double

    public init(tapThreshold: Double = 0.3) {
        self.tapThreshold = tapThreshold
    }

    public var isVisible: Bool {
        switch state {
        case .holding, .pinned: return true
        case .hidden, .releasing: return false
        }
    }

    public var isPinned: Bool { state == .pinned }

    public mutating func handle(_ event: Event) -> [Effect] {
        switch (state, event) {
        case (.hidden, .shortcutDown(let time)):
            state = .holding(since: time)
            return [.show]

        case (.hidden, .pin):
            state = .pinned
            return [.show, .makeInteractive]

        case (.holding(let since), .shortcutUp(let time)):
            if time - since <= tapThreshold {
                state = .pinned
                return [.makeInteractive]
            }
            state = .hidden
            return [.hide]

        case (.holding, .pin):
            // The upcoming key-up no longer means "let go".
            state = .pinned
            return [.makeInteractive]

        case (.holding, .shortcutCancelled), (.holding, .dismiss):
            state = .releasing
            return [.hide]

        case (.pinned, .shortcutDown):
            state = .releasing
            return [.hide]

        case (.pinned, .dismiss):
            state = .hidden
            return [.hide]

        case (.releasing, .shortcutUp), (.releasing, .shortcutCancelled):
            state = .hidden
            return []

        case (.releasing, .shortcutDown(let time)):
            // A key-up went missing; treat this as a fresh press.
            state = .holding(since: time)
            return [.show]

        case (.releasing, .pin):
            state = .pinned
            return [.show, .makeInteractive]

        default:
            // Key repeat while holding, stray key-ups, dismissing when hidden.
            return []
        }
    }
}
