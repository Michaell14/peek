import AppKit

/// The full-screen window the overlay lives in.
///
/// It is a non-activating panel so that showing it never takes the user out
/// of the app, the full-screen space, or the text field they were in.
final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // Above the menu bar and Dock, below menus and pop-ups so that
        // context menus and page drop-downs still appear on top.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        // The overlay is a dark sheet over whatever is behind it, whatever
        // the system appearance is.
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        return EditingShortcuts.perform(event, from: self)
    }
}

/// The app has no visible menu bar of its own while the overlay is up, so its
/// windows pass the standard editing shortcuts to text fields and web pages
/// themselves.
enum EditingShortcuts {
    @MainActor
    static func perform(_ event: NSEvent, from sender: NSWindow) -> Bool {
        guard event.type == .keyDown else { return false }

        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let action: Selector?
        switch (flags, key) {
        case (.command, "x"): action = #selector(NSText.cut(_:))
        case (.command, "c"): action = #selector(NSText.copy(_:))
        case (.command, "v"): action = #selector(NSText.paste(_:))
        case (.command, "a"): action = #selector(NSText.selectAll(_:))
        case (.command, "z"): action = Selector(("undo:"))
        case ([.command, .shift], "z"): action = Selector(("redo:"))
        default: action = nil
        }
        guard let action else { return false }
        return NSApp.sendAction(action, to: nil, from: sender)
    }
}
