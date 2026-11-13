import AppKit
import BlinkCore

/// What a tile's content needs from the rest of the app.
@MainActor
struct TileContext {
    let model: AppModel
    let boardID: UUID
    let web: WebEnvironment
    /// Called when a web tile enters or leaves "hide elements" mode.
    let pickerDidChange: @MainActor () -> Void
    /// Opens the "add something" palette.
    let presentLauncher: @MainActor () -> Void
    /// Puts a template on the board to try, with the choice to keep it.
    let previewTemplate: @MainActor (BoardTemplate) -> Void
}

/// Base class for whatever a tile shows: a web page, a file or a widget.
class TileContentView: FlippedView {
    let context: TileContext
    private(set) var tile: Tile
    private(set) var settings: AppSettings
    /// Set by the owning tile so it can refresh its label.
    var titleDidChange: (() -> Void)?

    init(tile: Tile, settings: AppSettings, context: TileContext) {
        self.tile = tile
        self.settings = settings
        self.context = context
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Short label shown while arranging tiles.
    var title: String { "" }

    /// SF Symbol shown with the label while arranging tiles.
    var symbolName: String { "square" }

    /// Called whenever the saved tile or the settings change.
    func apply(tile: Tile, settings: AppSettings) {
        self.tile = tile
        self.settings = settings
    }

    func overlayWillShow() {}
    func overlayDidHide() {}
    func interactivityDidChange(_ isInteractive: Bool) {}

    /// Items for the tile's "more" menu, above the shared ones.
    func addMenuItems(to menu: NSMenu) {}

    /// Continue with this content outside the overlay.
    func openExternally() {}

    /// Release anything that would otherwise keep running.
    func tearDown() {}

    func updateTile(_ change: (inout Tile) -> Void) {
        context.model.updateTile(tile.id, in: context.boardID, change)
    }

    func dismissOverlay() {
        NotificationCenter.default.post(name: .blinkDismissOverlay, object: nil)
    }
}

/// A centred message with an optional button, for empty and error states.
final class MessageView: NSView {
    private let action: (@MainActor () -> Void)?

    init(symbol: String, text: String, buttonTitle: String? = nil, action: (@MainActor () -> Void)? = nil) {
        self.action = action
        super.init(frame: .zero)

        let icon = NSImageView(image: .symbol(symbol, description: ""))
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .light)
        icon.contentTintColor = .tertiaryLabelColor

        let label = NSTextField(wrappingLabelWithString: text)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13)
        label.isSelectable = false

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let buttonTitle {
            let button = NSButton(title: buttonTitle, target: self, action: #selector(runAction))
            button.bezelStyle = .rounded
            button.controlSize = .large
            stack.addArrangedSubview(button)
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func runAction() {
        action?()
    }
}
