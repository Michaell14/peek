import AppKit
import GanderCore

/// For callbacks that AppKit, WebKit and Carbon always deliver on the main
/// thread but whose signatures do not say so.
@discardableResult
func onMainActor<T: Sendable>(_ body: @MainActor () -> T) -> T {
    MainActor.assumeIsolated(body)
}

extension LayoutRect {
    init(_ rect: CGRect) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.size.width),
            height: Double(rect.size.height)
        )
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

extension LayoutSize {
    init(_ size: CGSize) {
        self.init(width: Double(size.width), height: Double(size.height))
    }
}

extension LayoutPoint {
    init(_ point: CGPoint) {
        self.init(x: Double(point.x), y: Double(point.y))
    }
}

/// A plain container whose origin is the top-left corner.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

extension NSView {
    func pinToSuperviewEdges() {
        guard let superview else { return }
        frame = superview.bounds
        autoresizingMask = [.width, .height]
    }
}

extension NSImage {
    static func symbol(_ name: String, description: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: description)
            ?? NSImage(size: NSSize(width: 16, height: 16))
    }
}

extension NSMenu {
    /// Adds an item whose action is a closure instead of a selector.
    @discardableResult
    func addItem(
        _ title: String,
        checked: Bool = false,
        enabled: Bool = true,
        action: @escaping @MainActor () -> Void
    ) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: action)
        item.state = checked ? .on : .off
        item.isEnabled = enabled
        addItem(item)
        return item
    }

    @discardableResult
    func addSubmenu(_ title: String, build: (NSMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        build(submenu)
        item.submenu = submenu
        addItem(item)
        return item
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        onMainActor { handler() }
    }
}

enum SystemSettings {
    static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openInputMonitoring() { open("Privacy_ListenEvent") }
    static func openCalendars() { open("Privacy_Calendars") }
    static func openReminders() { open("Privacy_Reminders") }
}

extension Notification.Name {
    /// Posted by anything that needs the overlay out of the way, such as a
    /// system permission prompt that would otherwise open behind it.
    static let ganderDismissOverlay = Notification.Name("GanderDismissOverlay")
}
