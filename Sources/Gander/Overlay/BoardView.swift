import AppKit
import GanderCore

/// Draws the alignment lines that appear while a tile snaps into place.
private final class GuideOverlayView: FlippedView {
    var lines: [(from: CGPoint, to: CGPoint)] = [] {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard !lines.isEmpty else { return }
        let path = NSBezierPath()
        for line in lines {
            path.move(to: line.from)
            path.line(to: line.to)
        }
        path.lineWidth = 1
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}

/// One board's canvas: creates a view per tile, positions them according to
/// the board's layout mode, and handles moving and resizing while arranging.
final class BoardView: FlippedView {
    let boardID: UUID
    private(set) var board: Board
    private var settings: AppSettings
    private let context: TileContext
    private var tileViews: [UUID: TileView] = [:]
    private let guideView = GuideOverlayView()
    private let emptyView = MessageView(
        symbol: "plus.rectangle.on.rectangle",
        text: "Nothing here yet.\nPress + to add a website, a file or a widget."
    )
    private var drag: DragSession?

    /// Height kept clear at the top for the menu bar strip and toolbar.
    var topInset: CGFloat = 0 {
        didSet {
            if topInset != oldValue { needsLayout = true }
        }
    }

    var isEditing = false {
        didSet {
            guard isEditing != oldValue else { return }
            tileViews.values.forEach { $0.isEditing = isEditing }
            if !isEditing { cancelDrag() }
            updateHover()
        }
    }

    var isInteractive = false {
        didSet {
            guard isInteractive != oldValue else { return }
            tileViews.values.forEach { $0.isInteractive = isInteractive }
            updateHover()
        }
    }

    private struct DragSession {
        let tileID: UUID
        /// nil while moving; the grabbed edge or corner while resizing.
        let handle: ResizeHandle?
        let startPointer: CGPoint
        /// The tile's frame when the drag began, relative to the canvas.
        let startFrame: LayoutRect
        var currentFrame: LayoutRect
        /// Flow mode: order and sizes as they would be if the drag ended now.
        var flowItems: [FlowLayout.Item]
    }

    init(board: Board, settings: AppSettings, context: TileContext) {
        boardID = board.id
        self.board = board
        self.settings = settings
        self.context = context
        super.init(frame: .zero)
        addSubview(emptyView)
        addSubview(guideView)
        // Guides stay visible above a tile that is lifted while dragging.
        guideView.wantsLayer = true
        guideView.layer?.zPosition = 2
        apply(board: board, settings: settings)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Model

    /// Brings the views in line with the saved board.
    func apply(board: Board, settings: AppSettings) {
        self.board = board
        self.settings = settings

        var seen = Set<UUID>()
        for tile in board.tiles {
            seen.insert(tile.id)
            if let view = tileViews[tile.id] {
                view.apply(tile: tile, settings: settings)
            } else {
                let view = TileView(tile: tile, settings: settings, context: context)
                view.board = self
                view.isInteractive = isInteractive
                view.isEditing = isEditing
                tileViews[tile.id] = view
                addSubview(view, positioned: .below, relativeTo: guideView)
            }
        }
        for (id, view) in tileViews where !seen.contains(id) {
            view.tearDown()
            view.removeFromSuperview()
            tileViews[id] = nil
        }

        restack()
        emptyView.isHidden = !board.tiles.isEmpty
        layoutTiles(animated: window?.isVisible == true && drag == nil)
    }

    func tearDown() {
        tileViews.values.forEach { $0.tearDown() }
    }

    func removeTile(_ id: UUID) {
        context.model.update { $0.removeTile(id, from: boardID) }
    }

    var contentViews: [TileContentView] {
        board.tiles.compactMap { tileViews[$0.id]?.content }
    }

    func frame(ofTile id: UUID) -> CGRect? {
        tileViews[id]?.frame
    }

    /// The frame of a tile's hover controls in this view's coordinates, or
    /// nil while they are hidden.
    func controlsFrame(ofTile id: UUID) -> CGRect? {
        guard let view = tileViews[id], view.isShowingControls else { return nil }
        return view.controlsFrame.offsetBy(dx: view.frame.minX, dy: view.frame.minY)
    }

    func overlayWillShow() {
        contentViews.forEach { $0.overlayWillShow() }
    }

    func overlayDidHide() {
        contentViews.forEach { $0.overlayDidHide() }
    }

    func ruleListsDidChange() {
        for case let web as WebTileContentView in contentViews {
            web.ruleListsDidChange()
        }
    }

    var isPicking: Bool {
        contentViews.contains { ($0 as? WebTileContentView)?.isPicking == true }
    }

    func stopPicking() {
        for case let web as WebTileContentView in contentViews {
            web.stopPicker()
        }
    }

    /// The web tile under the pointer, for keyboard shortcuts like ⌘R.
    func webTileUnderPointer() -> WebTileContentView? {
        guard let window else { return nil }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        for tile in board.tiles.reversed() {
            if let view = tileViews[tile.id], view.frame.contains(point) {
                return view.content as? WebTileContentView
            }
        }
        return nil
    }

    // MARK: - Hover

    /// Works out which tile the pointer is over, from where the pointer is
    /// rather than from enter and exit events. The overlay calls this
    /// repeatedly while it is open: its window belongs to an app that is
    /// never frontmost, and pointer events do not reliably reach such a
    /// window.
    func updateHover() {
        var hovered: UUID?
        if isInteractive, !isEditing, let window {
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            // Topmost first.
            hovered = board.tiles.reversed().first { tileViews[$0.id]?.frame.contains(point) == true }?.id
        }
        for (id, view) in tileViews {
            view.isHovering = id == hovered
        }
    }

    // MARK: - Layout

    /// The area tiles may occupy, in this view's coordinates.
    private var canvasFrame: CGRect {
        // Whole points throughout, so positions survive being saved and
        // laid out again without drifting.
        let padding = CGFloat(settings.canvasPadding.rounded())
        let top = (topInset + 6).rounded()
        return CGRect(
            x: padding,
            y: top,
            width: max(bounds.width - 2 * padding, 1),
            height: max(bounds.height - top - padding, 1)
        )
    }

    private var flowOptions: FlowLayout.Options {
        FlowLayout.Options(gap: settings.tileGap.rounded(), minWidth: 180, minHeight: 90)
    }

    private var snapOptions: SnapOptions {
        SnapOptions(isEnabled: settings.snapToGuides, threshold: 8, gap: settings.tileGap.rounded())
    }

    private var savedFlowItems: [FlowLayout.Item] {
        board.tiles.map { FlowLayout.Item(id: $0.id, width: $0.flowWidth, height: $0.flowHeight) }
    }

    /// Where every tile belongs, relative to the canvas.
    private func canvasFrames() -> [UUID: LayoutRect] {
        let size = LayoutSize(canvasFrame.size)
        switch board.mode {
        case .flow:
            return FlowLayout.layout(drag?.flowItems ?? savedFlowItems, in: size, options: flowOptions)
        case .freeform:
            var frames: [UUID: LayoutRect] = [:]
            for tile in board.tiles {
                frames[tile.id] = FreeformLayout.clamp(tile.frame.scaled(to: size), to: size).integral
            }
            return frames
        }
    }

    private func viewFrame(_ rect: LayoutRect) -> CGRect {
        let canvas = canvasFrame
        return rect.cgRect.offsetBy(dx: canvas.minX, dy: canvas.minY)
    }

    override func layout() {
        super.layout()
        guideView.frame = bounds
        emptyView.frame = canvasFrame
        layoutTiles(animated: false)
    }

    private func layoutTiles(animated: Bool) {
        let frames = canvasFrames()
        // A tile being moved follows the pointer, not the layout.
        let floating = drag.flatMap { $0.handle == nil ? $0.tileID : nil }

        func place() {
            for (id, view) in tileViews where id != floating {
                guard let rect = frames[id] else { continue }
                let target = viewFrame(rect)
                if view.frame != target {
                    (animated ? view.animator() : view).frame = target
                }
            }
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.allowsImplicitAnimation = true
                place()
            }
        } else {
            place()
        }
    }

    /// Keeps the view order matching the tile order (which is back-to-front
    /// in freeform mode), touching the hierarchy only when it is wrong.
    private func restack() {
        let wanted = board.tiles.compactMap { tileViews[$0.id] }
        let current = subviews.compactMap { $0 as? TileView }
        guard wanted.map(\.tileID) != current.map(\.tileID) else { return }
        for view in wanted {
            addSubview(view, positioned: .below, relativeTo: guideView)
        }
    }

    // MARK: - Changing layout mode

    /// Switches mode while keeping tiles where they currently appear, so the
    /// change is a starting point rather than a reshuffle.
    func setMode(_ mode: LayoutMode) {
        guard mode != board.mode else { return }
        let canvas = canvasFrame
        let size = LayoutSize(canvas.size)
        let current = canvasFrames()

        // Would the tiles' saved flow sizes put them where they are now?
        let saved = FlowLayout.layout(savedFlowItems, in: size, options: flowOptions)
        let isUnchangedSinceFlow = board.tiles.allSatisfy { tile in
            guard let now = current[tile.id], let then = saved[tile.id] else { return false }
            return abs(now.x - then.x) <= 1.5 && abs(now.y - then.y) <= 1.5
                && abs(now.width - then.width) <= 1.5 && abs(now.height - then.height) <= 1.5
        }

        context.model.update { workspace in
            workspace.updateBoard(boardID) { board in
                switch mode {
                case .freeform:
                    for index in board.tiles.indices {
                        if let rect = current[board.tiles[index].id] {
                            board.tiles[index].frame = rect.normalized(in: size)
                        }
                    }
                case .flow:
                    // Nothing was rearranged while in freeform: the flow
                    // settings from before still describe the board exactly.
                    if isUnchangedSinceFlow { break }
                    // Otherwise read columns, order and sizes off the canvas.
                    let items = FlowLayout.items(
                        from: board.tiles.compactMap { tile in current[tile.id].map { (tile.id, $0) } },
                        canvasHeight: size.height,
                        options: flowOptions
                    )
                    var byID: [UUID: Tile] = [:]
                    for tile in board.tiles {
                        byID[tile.id] = tile
                    }
                    board.tiles = items.compactMap { item in
                        guard var tile = byID[item.id] else { return nil }
                        tile.flowWidth = item.width
                        tile.flowHeight = item.height
                        return tile
                    }
                }
                board.mode = mode
            }
        }
    }

    /// A free spot for a new tile, as fractions of the canvas.
    func frameForNewTile(_ content: TileContent) -> LayoutRect {
        let size = LayoutSize(canvasFrame.size)
        let sizing = Tile.defaultSizing(for: content)
        let wanted = LayoutSize(
            width: min(sizing.width, size.width),
            height: min(sizing.height ?? size.height * 0.8, size.height)
        )
        let existing = Array(canvasFrames().values)
        return FreeformLayout.placeNew(size: wanted, in: size, existing: existing, gap: settings.tileGap.rounded())
            .normalized(in: size)
    }

    // MARK: - Dragging

    func beginDrag(_ tileView: TileView, handle: ResizeHandle?, event: NSEvent) {
        let canvas = canvasFrame
        let start = LayoutRect(tileView.frame.offsetBy(dx: -canvas.minX, dy: -canvas.minY))
        drag = DragSession(
            tileID: tileView.tileID,
            handle: handle,
            startPointer: convert(event.locationInWindow, from: nil),
            startFrame: start,
            currentFrame: start,
            flowItems: savedFlowItems
        )
        // Lift the tile above its neighbours without moving it in the view
        // hierarchy, which would interrupt the drag in progress.
        tileView.layer?.zPosition = 1
    }

    func continueDrag(with event: NSEvent) {
        guard var session = drag, let tileView = tileViews[session.tileID] else { return }
        let pointer = convert(event.locationInWindow, from: nil)
        let delta = LayoutPoint(x: pointer.x - session.startPointer.x, y: pointer.y - session.startPointer.y)
        let canvas = canvasFrame
        let size = LayoutSize(canvas.size)

        switch (board.mode, session.handle) {
        case (.freeform, let handle):
            let others = canvasFrames().filter { $0.key != session.tileID }.map(\.value)
            let result: FreeformLayout.Result
            if let handle {
                result = FreeformLayout.resize(
                    session.startFrame, handle: handle, by: delta, in: size, others: others, snap: snapOptions
                )
            } else {
                result = FreeformLayout.move(session.startFrame, by: delta, in: size, others: others, snap: snapOptions)
            }
            session.currentFrame = result.rect
            drag = session
            tileView.frame = viewFrame(result.rect.integral)
            showGuides(result.guides)

        case (.flow, nil):
            session.currentFrame = session.startFrame.offsetBy(dx: delta.x, dy: delta.y)
            tileView.frame = viewFrame(session.currentFrame)

            let point = LayoutPoint(x: pointer.x - canvas.minX, y: pointer.y - canvas.minY)
            let index = FlowLayout.insertionIndex(
                at: point, moving: session.tileID, items: session.flowItems, in: size, options: flowOptions
            )
            var items = session.flowItems
            if let from = items.firstIndex(where: { $0.id == session.tileID }) {
                let item = items.remove(at: from)
                items.insert(item, at: min(index, items.count))
            }
            let reordered = items != session.flowItems
            session.flowItems = items
            drag = session
            if reordered { layoutTiles(animated: true) }

        case (.flow, let handle?):
            guard let index = session.flowItems.firstIndex(where: { $0.id == session.tileID }) else { return }
            var item = session.flowItems[index]
            // The row of columns is centred, so an edge moves half as far as
            // the width changes; doubling keeps it under the pointer.
            if handle.movesRight { item.width = session.startFrame.width + 2 * delta.x }
            if handle.movesLeft { item.width = session.startFrame.width - 2 * delta.x }
            item.width = min(max(item.width, flowOptions.minWidth), size.width)

            if handle.movesBottom || handle.movesTop {
                let height = session.startFrame.height + (handle.movesBottom ? delta.y : -delta.y)
                // Dragged to (nearly) full height means "fill the column".
                item.height = height >= size.height - 24 ? nil : max(height, flowOptions.minHeight)
            }
            session.flowItems[index] = item
            drag = session
            layoutTiles(animated: false)
        }
    }

    func endDrag() {
        guard let session = drag else { return }
        drag = nil
        guideView.lines = []
        tileViews[session.tileID]?.layer?.zPosition = 0
        let size = LayoutSize(canvasFrame.size)
        let id = session.tileID

        switch (board.mode, session.handle) {
        case (.freeform, _):
            context.model.update { workspace in
                workspace.updateTile(id, in: boardID) { $0.frame = session.currentFrame.normalized(in: size) }
                workspace.bringTileToFront(id, in: boardID)
            }
        case (.flow, nil):
            if let index = session.flowItems.firstIndex(where: { $0.id == id }) {
                context.model.update { $0.moveTile(id, in: boardID, to: index) }
            }
        case (.flow, _?):
            if let item = session.flowItems.first(where: { $0.id == id }) {
                context.model.updateTile(id, in: boardID) { tile in
                    tile.flowWidth = item.width
                    tile.flowHeight = item.height
                }
            }
        }
        // Covers the case where nothing changed and the model stays quiet.
        layoutTiles(animated: true)
    }

    private func cancelDrag() {
        guard let session = drag else { return }
        drag = nil
        guideView.lines = []
        tileViews[session.tileID]?.layer?.zPosition = 0
        restack()
        layoutTiles(animated: true)
    }

    private func showGuides(_ guides: [SnapGuide]) {
        let canvas = canvasFrame
        guideView.lines = guides.map { guide in
            switch guide.axis {
            case .vertical:
                let x = canvas.minX + CGFloat(guide.position)
                return (CGPoint(x: x, y: canvas.minY), CGPoint(x: x, y: canvas.maxY))
            case .horizontal:
                let y = canvas.minY + CGFloat(guide.position)
                return (CGPoint(x: canvas.minX, y: y), CGPoint(x: canvas.maxX, y: y))
            }
        }
    }
}
