import AppKit
import GanderCore

/// One tile on a board: its content, the controls that appear on hover, and
/// the cover used to move and resize it while arranging.
final class TileView: FlippedView {
    let tileID: UUID
    let content: TileContentView
    weak var board: BoardView?

    private(set) var tile: Tile
    private let chrome: TileChromeView
    private let editCover = TileEditCover()
    private var isHovering = false

    var isEditing = false {
        didSet {
            editCover.isHidden = !isEditing
            editCover.title = content.title
            updateChrome()
        }
    }

    var isInteractive = false {
        didSet {
            content.interactivityDidChange(isInteractive)
            // Enter/exit events stop while the overlay is hidden, so work out
            // afresh whether the pointer is over this tile.
            isHovering = isInteractive && containsPointer
            updateChrome()
        }
    }

    private var containsPointer: Bool {
        guard let window else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    init(tile: Tile, settings: AppSettings, context: TileContext) {
        tileID = tile.id
        self.tile = tile
        content = TileView.makeContent(tile: tile, settings: settings, context: context)
        chrome = TileChromeView(showsNavigation: content is WebTileContentView)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.11, alpha: 0.97).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.1).cgColor
        layer?.cornerRadius = settings.tileCornerRadius

        addSubview(content)
        content.pinToSuperviewEdges()
        content.titleDidChange = { [weak self] in
            guard let self else { return }
            self.editCover.title = self.content.title
        }

        chrome.isHidden = true
        chrome.onBack = { [weak self] in (self?.content as? WebTileContentView)?.goBack() }
        chrome.onForward = { [weak self] in (self?.content as? WebTileContentView)?.goForward() }
        chrome.onReload = { [weak self] in (self?.content as? WebTileContentView)?.reload() }
        chrome.onMenu = { [weak self] button in self?.showMenu(from: button) }
        addSubview(chrome)

        editCover.tileView = self
        editCover.isHidden = true
        addSubview(editCover)
        editCover.pinToSuperviewEdges()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func makeContent(tile: Tile, settings: AppSettings, context: TileContext) -> TileContentView {
        switch tile.content {
        case .web(let web):
            return WebTileContentView(tile: tile, web: web, settings: settings, context: context)
        case .file(let file):
            return FileTileContentView(tile: tile, file: file, settings: settings, context: context)
        case .widget(let widget):
            return WidgetTileContentView(tile: tile, widget: widget, settings: settings, context: context)
        }
    }

    func apply(tile: Tile, settings: AppSettings) {
        self.tile = tile
        layer?.cornerRadius = settings.tileCornerRadius
        content.apply(tile: tile, settings: settings)
    }

    func tearDown() {
        content.tearDown()
    }

    // MARK: - Hover controls

    override func layout() {
        super.layout()
        let size = chrome.preferredSize
        chrome.frame = CGRect(x: bounds.width - size.width - 8, y: 8, width: size.width, height: size.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        // .activeAlways: the overlay belongs to an app that is never frontmost.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateChrome()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateChrome()
    }

    private func updateChrome() {
        let visible = isHovering && isInteractive && !isEditing
        if visible, let web = content as? WebTileContentView {
            chrome.setNavigation(canGoBack: web.canGoBack, canGoForward: web.canGoForward)
        }
        // Hidden rather than faded out: an invisible button would still take
        // clicks meant for the page underneath.
        chrome.isHidden = !visible
    }

    // MARK: - Menu

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        content.addMenuItems(to: menu)
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        menu.addItem("Remove Tile") { [weak self] in
            guard let self else { return }
            self.board?.removeTile(self.tileID)
        }
        return menu
    }

    private func showMenu(from button: NSView) {
        _ = makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    func remove() {
        board?.removeTile(tileID)
    }
}

/// The small pill of buttons at a tile's top-right corner.
final class TileChromeView: NSVisualEffectView {
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onReload: (() -> Void)?
    var onMenu: ((NSView) -> Void)?

    private var backButton: NSButton?
    private var forwardButton: NSButton?
    private let stack = NSStackView()
    private let buttonSize: CGFloat = 24

    init(showsNavigation: Bool) {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true

        stack.orientation = .horizontal
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        addSubview(stack)

        if showsNavigation {
            let back = makeButton("chevron.left", "Back", #selector(backPressed))
            let forward = makeButton("chevron.right", "Forward", #selector(forwardPressed))
            backButton = back
            forwardButton = forward
            stack.addArrangedSubview(back)
            stack.addArrangedSubview(forward)
            stack.addArrangedSubview(makeButton("arrow.clockwise", "Reload", #selector(reloadPressed)))
        }
        stack.addArrangedSubview(makeButton("ellipsis", "More", #selector(menuPressed(_:))))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var preferredSize: CGSize {
        CGSize(width: CGFloat(stack.arrangedSubviews.count) * buttonSize + 8, height: buttonSize + 4)
    }

    override func layout() {
        super.layout()
        stack.frame = bounds
    }

    func setNavigation(canGoBack: Bool, canGoForward: Bool) {
        backButton?.isEnabled = canGoBack
        forwardButton?.isEnabled = canGoForward
    }

    private func makeButton(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: .symbol(symbol, description: label), target: self, action: action)
        button.isBordered = false
        button.contentTintColor = .labelColor
        button.toolTip = label
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: buttonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: buttonSize).isActive = true
        return button
    }

    @objc private func backPressed() { onBack?() }
    @objc private func forwardPressed() { onForward?() }
    @objc private func reloadPressed() { onReload?() }
    @objc private func menuPressed(_ sender: NSButton) { onMenu?(sender) }
}

/// Sits over a tile while arranging. It keeps clicks away from the content
/// and turns drags into moves and resizes.
final class TileEditCover: FlippedView {
    weak var tileView: TileView?

    var title = "" {
        didSet { label.stringValue = title }
    }

    private let label = NSTextField(labelWithString: "")
    private let removeButton = NSButton()
    /// How close to an edge a press must be to grab it.
    private let grip: CGFloat = 14

    init() {
        super.init(frame: .zero)

        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        removeButton.image = .symbol("xmark.circle.fill", description: "Remove")
        removeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        removeButton.isBordered = false
        removeButton.contentTintColor = .white
        removeButton.toolTip = "Remove"
        removeButton.target = self
        removeButton.action = #selector(removePressed)
        addSubview(removeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        removeButton.frame = CGRect(x: 10, y: 10, width: 24, height: 24)
        let height: CGFloat = 20
        label.frame = CGRect(x: 40, y: (bounds.height - height) / 2, width: max(bounds.width - 80, 0), height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.5).setFill()
        bounds.fill()

        // Corner brackets hint at where to grab for resizing.
        let inset: CGFloat = 7
        let length: CGFloat = 16
        let frame = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath()
        for (corner, dx, dy) in [
            (CGPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0),
            (CGPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0),
            (CGPoint(x: frame.maxX, y: frame.maxY), -1.0, -1.0),
        ] {
            path.move(to: CGPoint(x: corner.x + CGFloat(dx) * length, y: corner.y))
            path.line(to: corner)
            path.line(to: CGPoint(x: corner.x, y: corner.y + CGFloat(dy) * length))
        }
        path.lineWidth = 2.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor(white: 1, alpha: 0.85).setStroke()
        path.stroke()
    }

    /// Everything on the tile belongs to the cover while arranging, apart
    /// from the remove button.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let superview, frame.contains(point) else { return nil }
        let local = convert(point, from: superview)
        return removeButton.frame.contains(local) ? removeButton : self
    }

    /// Which edge or corner a point grabs, or nil for the middle (a move).
    private func handle(at point: CGPoint) -> ResizeHandle? {
        let left = point.x < grip
        let right = point.x > bounds.width - grip
        let top = point.y < grip
        let bottom = point.y > bounds.height - grip
        switch (left, right, top, bottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let tileView, let board = tileView.board else { return }
        let point = convert(event.locationInWindow, from: nil)
        board.beginDrag(tileView, handle: handle(at: point), event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        tileView?.board?.continueDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        tileView?.board?.endDrag()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let tileView else { return }
        NSMenu.popUpContextMenu(tileView.makeMenu(), with: event, for: self)
    }

    override func resetCursorRects() {
        let width = bounds.width
        let height = bounds.height
        addCursorRect(bounds.insetBy(dx: grip, dy: grip), cursor: .openHand)
        addCursorRect(CGRect(x: 0, y: grip, width: grip, height: height - 2 * grip), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: width - grip, y: grip, width: grip, height: height - 2 * grip), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: grip, y: 0, width: width - 2 * grip, height: grip), cursor: .resizeUpDown)
        addCursorRect(CGRect(x: grip, y: height - grip, width: width - 2 * grip, height: grip), cursor: .resizeUpDown)
        for x in [0, width - grip] {
            for y in [0, height - grip] {
                addCursorRect(CGRect(x: x, y: y, width: grip, height: grip), cursor: .crosshair)
            }
        }
    }

    @objc private func removePressed() {
        tileView?.remove()
    }
}
