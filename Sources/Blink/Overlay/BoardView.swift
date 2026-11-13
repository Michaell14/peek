import AppKit
import BlinkCore

/// One board's canvas: creates a view per tile, packs them into columns, and
/// handles moving and resizing while arranging.
final class BoardView: FlippedView {
    let boardID: UUID
    private(set) var board: Board
    private var settings: AppSettings
    private let context: TileContext
    private var tileViews: [UUID: TileView] = [:]
    private let emptyView: MessageView
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
        /// Order and sizes as they would be if the drag ended now.
        var flowItems: [FlowLayout.Item]
    }

    init(board: Board, settings: AppSettings, context: TileContext) {
        boardID = board.id
        self.board = board
        self.settings = settings
        self.context = context
        emptyView = MessageView(
            symbol: "rectangle.3.group",
            text: "Nothing here yet.\nAdd a website, a file or a widget to get started.",
            buttonTitle: "Add Something",
            action: context.presentLauncher
        )
        super.init(frame: .zero)
        addSubview(emptyView)
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
                addSubview(view)
            }
        }
        for (id, view) in tileViews where !seen.contains(id) {
            view.tearDown()
            view.removeFromSuperview()
            tileViews[id] = nil
        }

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
        let top = (topInset + 4).rounded()
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

    private var savedFlowItems: [FlowLayout.Item] {
        board.tiles.map { FlowLayout.Item(id: $0.id, width: $0.flowWidth, height: $0.flowHeight) }
    }

    /// Where every tile belongs, relative to the canvas.
    private func canvasFrames() -> [UUID: LayoutRect] {
        FlowLayout.layout(drag?.flowItems ?? savedFlowItems, in: LayoutSize(canvasFrame.size), options: flowOptions)
    }

    private func viewFrame(_ rect: LayoutRect) -> CGRect {
        let canvas = canvasFrame
        return rect.cgRect.offsetBy(dx: canvas.minX, dy: canvas.minY)
    }

    override func layout() {
        super.layout()
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
        tileView.setDragging(true, size: handle == nil ? nil : tileView.frame.size)
    }

    func continueDrag(with event: NSEvent) {
        guard var session = drag, let tileView = tileViews[session.tileID] else { return }
        let pointer = convert(event.locationInWindow, from: nil)
        let delta = LayoutPoint(x: pointer.x - session.startPointer.x, y: pointer.y - session.startPointer.y)
        let canvas = canvasFrame
        let size = LayoutSize(canvas.size)

        switch session.handle {
        case nil:
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

        case let handle?:
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
            tileView.setDragging(true, size: tileView.frame.size)
        }
    }

    func endDrag() {
        guard let session = drag else { return }
        drag = nil
        tileViews[session.tileID]?.layer?.zPosition = 0
        tileViews[session.tileID]?.setDragging(false)
        let id = session.tileID

        switch session.handle {
        case nil:
            if let index = session.flowItems.firstIndex(where: { $0.id == id }) {
                context.model.update { $0.moveTile(id, in: boardID, to: index) }
            }
        case _?:
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
        tileViews[session.tileID]?.layer?.zPosition = 0
        tileViews[session.tileID]?.setDragging(false)
        layoutTiles(animated: true)
    }
}
