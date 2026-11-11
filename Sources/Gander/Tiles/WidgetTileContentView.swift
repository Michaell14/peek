import AppKit
import GanderCore
import SwiftUI

/// Hosts one of the built-in SwiftUI widgets.
final class WidgetTileContentView: TileContentView {
    private var widget: WidgetContent
    private let host = NSHostingView(rootView: AnyView(EmptyView()))

    init(tile: Tile, widget: WidgetContent, settings: AppSettings, context: TileContext) {
        self.widget = widget
        super.init(tile: tile, settings: settings, context: context)
        // The tile decides the size; the widget fills whatever it is given.
        host.sizingOptions = []
        addSubview(host)
        host.pinToSuperviewEdges()
        render()
    }

    override var title: String { widget.displayName }

    override func apply(tile: Tile, settings: AppSettings) {
        super.apply(tile: tile, settings: settings)
        guard case .widget(let updated) = tile.content, updated != widget else { return }
        widget = updated
        render()
    }

    override func openExternally() {
        let bundleID: String
        switch widget {
        case .clock: bundleID = "com.apple.clock"
        case .calendar: bundleID = "com.apple.iCal"
        case .reminders: bundleID = "com.apple.reminders"
        case .notes: return
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open(url)
            dismissOverlay()
        }
    }

    override func addMenuItems(to menu: NSMenu) {
        switch widget {
        case .clock:
            menu.addItem("Open Clock") { [weak self] in self?.openExternally() }
        case .calendar(let config):
            menu.addItem("Day", checked: config.mode == .day) { [weak self] in
                self?.save(.calendar(CalendarConfig(mode: .day)))
            }
            menu.addItem("Next 7 Days", checked: config.mode == .agenda) { [weak self] in
                self?.save(.calendar(CalendarConfig(mode: .agenda)))
            }
            menu.addItem(.separator())
            menu.addItem("Open Calendar") { [weak self] in self?.openExternally() }
        case .reminders:
            menu.addItem("Open Reminders") { [weak self] in self?.openExternally() }
        case .notes:
            break
        }
    }

    private func render() {
        switch widget {
        case .clock(let config):
            host.rootView = AnyView(ClockWidgetView(config: config) { [weak self] in self?.save(.clock($0)) })
        case .calendar(let config):
            host.rootView = AnyView(CalendarWidgetView(config: config) { [weak self] in self?.save(.calendar($0)) })
        case .reminders(let config):
            host.rootView = AnyView(RemindersWidgetView(config: config) { [weak self] in self?.save(.reminders($0)) })
        case .notes(let config):
            host.rootView = AnyView(NotesWidgetView(config: config) { [weak self] in self?.saveQuietly(.notes($0)) })
        }
    }

    /// Saves to the model, which comes back through `apply` and re-renders.
    private func save(_ updated: WidgetContent) {
        let previous = TileContent.widget(widget)
        updateTile { tile in
            // A tile still at its natural height follows its content (a
            // clock gaining a city); one the user resized is left alone.
            if tile.flowHeight == Tile.defaultSizing(for: previous).height {
                tile.flowHeight = Tile.defaultSizing(for: .widget(updated)).height
            }
            tile.content = .widget(updated)
        }
    }

    /// For changes the widget is already showing. Rebuilding the view under a
    /// text field on every keystroke would only cause churn.
    private func saveQuietly(_ updated: WidgetContent) {
        widget = updated
        save(updated)
    }
}
