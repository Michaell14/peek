import AppKit
import BlinkCore

/// One tile on a board: its content on a pane of dark glass, the controls
/// that appear on hover, and the cover used to move and resize it while
/// arranging.
final class TileView: FlippedView {
    let tileID: UUID
    let content: TileContentView
    weak var board: BoardView?

    private(set) var tile: Tile
    /// Rounds and clips everything inside the tile. The tile itself stays
    /// unclipped so that it can cast a shadow.
    private let clip = FlippedView()
    private let glass = NSVisualEffectView()
    private let tint = NSView()
    private let chrome: TileChromeView
    private let editCover = TileEditCover()
    private var cornerRadius: CGFloat
    private var isShowingChrome = false

    /// Set by the board, which knows where the pointer is.
    var isHovering = false {
        didSet {
            guard isHovering != oldValue else { return }
            updateChrome()
            updateBorder()
        }
    }

    var isEditing = false {
        didSet {
            editCover.isHidden = !isEditing
            editCover.title = content.title
            editCover.symbolName = content.symbolName
            updateChrome()
            updateBorder()
        }
    }

    var isInteractive = false {
        didSet {
            content.interactivityDidChange(isInteractive)
            updateChrome()
            updateBorder()
        }
    }

    /// Whether the hover controls are currently showing.
    var isShowingControls: Bool { isShowingChrome }

    /// Where the hover controls sit, in this view's coordinates.
    var controlsFrame: CGRect { chrome.frame }

    init(tile: Tile, settings: AppSettings, context: TileContext) {
        tileID = tile.id
        self.tile = tile
        cornerRadius = CGFloat(settings.tileCornerRadius)
        content = TileView.makeContent(tile: tile, settings: settings, context: context)
        chrome = TileChromeView(showsNavigation: content is WebTileContentView)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.38
        layer?.shadowRadius = 22
        layer?.shadowOffset = .zero

        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.layer?.cornerCurve = .continuous
        clip.layer?.borderWidth = 1
        addSubview(clip)
        clip.pinToSuperviewEdges()

        // Dark glass: what is behind the overlay shows through, blurred.
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        clip.addSubview(glass)
        glass.pinToSuperviewEdges()

        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(white: 0.04, alpha: 0.34).cgColor
        clip.addSubview(tint)
        tint.pinToSuperviewEdges()

        clip.addSubview(content)
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
        clip.addSubview(chrome)

        editCover.tileView = self
        editCover.isHidden = true
        clip.addSubview(editCover)
        editCover.pinToSuperviewEdges()

        applyCornerRadius()
        updateBorder()
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
        let radius = CGFloat(settings.tileCornerRadius)
        if radius != cornerRadius {
            cornerRadius = radius
            applyCornerRadius()
        }
        content.apply(tile: tile, settings: settings)
    }

    func tearDown() {
        content.tearDown()
    }

    // MARK: - Appearance

    private func applyCornerRadius() {
        clip.layer?.cornerRadius = cornerRadius
        glass.maskImage = .roundedMask(radius: cornerRadius)
        editCover.cornerRadius = cornerRadius
        needsLayout = true
    }

    private func updateBorder() {
        // A tile brightens a touch under the pointer.
        let lifted = isHovering && isInteractive && !isEditing
        clip.layer?.borderColor = (lifted ? NSColor(white: 1, alpha: 0.24) : Theme.stroke).cgColor
    }

    override func layout() {
        super.layout()
        // An explicit path spares the system working the shadow out from the
        // tile's contents on every frame.
        layer?.shadowPath = CGPath(
            roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil
        )
        let size = chrome.preferredSize
        chrome.frame = CGRect(x: bounds.width - size.width - 10, y: 10, width: size.width, height: size.height)
    }

    // MARK: - Hover controls

    private func updateChrome() {
        let visible = isHovering && isInteractive && !isEditing
        if visible, let web = content as? WebTileContentView {
            chrome.setNavigation(canGoBack: web.canGoBack, canGoForward: web.canGoForward)
        }
        guard visible != isShowingChrome else { return }
        isShowingChrome = visible

        if visible {
            chrome.alphaValue = 0
            chrome.isHidden = false
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            chrome.animator().alphaValue = visible ? 1 : 0
        }, completionHandler: { [weak self] in
            onMainActor {
                // Hidden once faded: an invisible button would still take
                // clicks meant for the page underneath.
                guard let self, !self.isShowingChrome else { return }
                self.chrome.isHidden = true
            }
        })
    }

    // MARK: - Arranging

    /// Marks the tile as the one being dragged, optionally showing its size.
    func setDragging(_ dragging: Bool, size: CGSize? = nil) {
        editCover.isActive = dragging
        editCover.sizeText = size.map { "\(Int($0.width.rounded())) × \(Int($0.height.rounded()))" }
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
        _ = makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 6), in: button)
    }

    func remove() {
        board?.removeTile(tileID)
    }
}

/// The small capsule of buttons at a tile's top-right corner.
final class TileChromeView: NSVisualEffectView {
    static let buttonSize: CGFloat = 26
    static let inset: CGFloat = 4

    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onReload: (() -> Void)?
    var onMenu: ((NSView) -> Void)?

    private var backButton: NSButton?
    private var forwardButton: NSButton?
    private let stack = NSStackView()

    init(showsNavigation: Bool) {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = (Self.buttonSize + 4) / 2
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(white: 1, alpha: 0.18).cgColor

        stack.orientation = .horizontal
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 2, left: Self.inset, bottom: 2, right: Self.inset)
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
        CGSize(
            width: CGFloat(stack.arrangedSubviews.count) * Self.buttonSize + 2 * Self.inset,
            height: Self.buttonSize + 4
        )
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
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        button.isBordered = false
        button.contentTintColor = .labelColor
        button.toolTip = label
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: Self.buttonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: Self.buttonSize).isActive = true
        return button
    }

    @objc private func backPressed() { onBack?() }
    @objc private func forwardPressed() { onForward?() }
    @objc private func reloadPressed() { onReload?() }
    @objc private func menuPressed(_ sender: NSButton) { onMenu?(sender) }
}

/// Sits over a tile while arranging. It keeps clicks away from the content,
/// shows where the tile can be grabbed, and turns drags into moves and
/// resizes.
final class TileEditCover: FlippedView {
    /// Where the remove button sits, in the cover's coordinates.
    static let removeButtonFrame = CGRect(x: 11, y: 11, width: 24, height: 24)

    weak var tileView: TileView?

    var title = "" {
        didSet { label.stringValue = title }
    }

    var symbolName = "square" {
        didSet { icon.image = .symbol(symbolName, description: "") }
    }

    var cornerRadius: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    /// True while this tile is the one being dragged.
    var isActive = false {
        didSet {
            if isActive != oldValue { needsDisplay = true }
        }
    }

    /// The tile's size while it is being resized, e.g. "460 × 713".
    var sizeText: String? {
        didSet {
            sizeBadge.stringValue = sizeText ?? ""
            sizeBadge.isHidden = sizeText == nil
            needsLayout = true
        }
    }

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let caption = NSStackView()
    private let removeButton = NSButton()
    private let sizeBadge = NSTextField(labelWithString: "")
    /// How close to an edge a press must be to grab it.
    private let grip: CGFloat = 14

    init() {
        super.init(frame: .zero)

        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        icon.contentTintColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        caption.orientation = .vertical
        caption.spacing = 8
        caption.alignment = .centerX
        caption.addArrangedSubview(icon)
        caption.addArrangedSubview(label)
        caption.translatesAutoresizingMaskIntoConstraints = false
        addSubview(caption)
        NSLayoutConstraint.activate([
            caption.centerXAnchor.constraint(equalTo: centerXAnchor),
            caption.centerYAnchor.constraint(equalTo: centerYAnchor),
            caption.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -44),
        ])

        removeButton.image = .symbol("xmark.circle.fill", description: "Remove")
        removeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 19, weight: .medium)
        removeButton.isBordered = false
        removeButton.contentTintColor = .white
        removeButton.toolTip = "Remove"
        removeButton.target = self
        removeButton.action = #selector(removePressed)
        addSubview(removeButton)

        sizeBadge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeBadge.textColor = .white
        sizeBadge.alignment = .center
        sizeBadge.wantsLayer = true
        sizeBadge.layer?.backgroundColor = NSColor(white: 0, alpha: 0.6).cgColor
        sizeBadge.layer?.cornerRadius = 10
        sizeBadge.isHidden = true
        addSubview(sizeBadge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        removeButton.frame = Self.removeButtonFrame
        let badgeWidth = sizeBadge.intrinsicContentSize.width + 18
        sizeBadge.frame = CGRect(
            x: (bounds.width - badgeWidth) / 2, y: bounds.height - 40, width: badgeWidth, height: 20
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.coverTint.setFill()
        bounds.fill()

        // An outline in the accent colour; stronger on the tile being moved.
        let outline = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            xRadius: max(cornerRadius - 1, 0), yRadius: max(cornerRadius - 1, 0)
        )
        outline.lineWidth = isActive ? 2 : 1.5
        Theme.accent.withAlphaComponent(isActive ? 1 : 0.6).setStroke()
        outline.stroke()

        // Grabbers: a bar on each edge and an arc in each corner (the
        // top-left corner is taken by the remove button).
        NSColor(white: 1, alpha: 0.9).set()
        let inset: CGFloat = 6
        let length: CGFloat = 32
        let thickness: CGFloat = 4
        if bounds.width > 120, bounds.height > 120 {
            let bars = [
                CGRect(x: bounds.midX - length / 2, y: inset, width: length, height: thickness),
                CGRect(x: bounds.midX - length / 2, y: bounds.maxY - inset - thickness, width: length, height: thickness),
                CGRect(x: inset, y: bounds.midY - length / 2, width: thickness, height: length),
                CGRect(x: bounds.maxX - inset - thickness, y: bounds.midY - length / 2, width: thickness, height: length),
            ]
            for bar in bars {
                NSBezierPath(roundedRect: bar, xRadius: thickness / 2, yRadius: thickness / 2).fill()
            }
        }

        let arcInset = inset + thickness / 2
        let radius = max(cornerRadius - arcInset, 7)
        let frame = bounds.insetBy(dx: arcInset, dy: arcInset)
        // In this flipped view angles run clockwise from the positive x axis.
        let corners: [(center: CGPoint, start: CGFloat)] = [
            (CGPoint(x: frame.maxX - radius, y: frame.minY + radius), 270),  // top right
            (CGPoint(x: frame.maxX - radius, y: frame.maxY - radius), 0),    // bottom right
            (CGPoint(x: frame.minX + radius, y: frame.maxY - radius), 90),   // bottom left
        ]
        for corner in corners {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: corner.center, radius: radius, startAngle: corner.start, endAngle: corner.start + 90)
            arc.lineWidth = thickness
            arc.lineCapStyle = .round
            arc.stroke()
        }
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
