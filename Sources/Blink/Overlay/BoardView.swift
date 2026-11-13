import AppKit
import BlinkCore
import SwiftUI

/// One board's canvas: creates a view per tile, lays them out in columns of
/// stacked tiles, and handles moving, stacking and resizing while arranging.
final class BoardView: FlippedView {
    let boardID: UUID
    private(set) var board: Board
    private var settings: AppSettings
    private let context: TileContext
    private var tileViews: [UUID: TileView] = [:]
    /// Tiles taken off the board while a template is being tried, kept
    /// alive (and hidden) so that putting the board back is instant and
    /// their pages do not load again.
    private var parked: [UUID: TileView] = [:]
    /// Shown while the board has no tiles: templates to start from.
    private let emptyView: NSView
    /// Which template card is under the pointer, on an empty board.
    let gallery: GalleryPointer
    private var drag: DragSession?

    /// Height kept clear at the top for the menu bar strip and toolbar.
    var topInset: CGFloat = 0 {
        didSet {
            if topInset != oldValue { needsLayout = true }
        }
    }

    /// Room kept clear along the bottom, for the shelf of templates.
    private(set) var bottomInset: CGFloat = 0

    /// While true, tiles taken off the board are parked rather than torn down.
    var parksRemovedTiles = false {
        didSet {
            if !parksRemovedTiles { flushParked() }
        }
    }

    /// Tiles on trial glow, so a template being tried never passes for the
    /// board itself.
    var isPreviewing = false {
        didSet {
            guard isPreviewing != oldValue else { return }
            tileViews.values.forEach { $0.isPreviewing = isPreviewing }
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
        /// Every tile's frame, and the arrangement, when the drag began.
        let startFrames: [UUID: LayoutRect]
        let startItems: [FlowLayout.Item]
        /// Where the row of columns started. It stays there for the whole
        /// drag rather than re-centring, so the columns being aimed at do
        /// not slide out from under the pointer as tiles make room.
        let originX: Double
        var currentFrame: LayoutRect
        /// The arrangement as it would be if the drag ended now.
        var flowItems: [FlowLayout.Item]
    }

    init(board: Board, settings: AppSettings, context: TileContext) {
        boardID = board.id
        self.board = board
        self.settings = settings
        self.context = context
        let gallery = GalleryPointer()
        self.gallery = gallery
        emptyView = NSHostingView(rootView: TemplateGallery(
            pointer: gallery,
            onChoose: context.useTemplate,
            onAdd: context.presentLauncher
        ))
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
        var appearing = Set<UUID>()
        for tile in board.tiles {
            seen.insert(tile.id)
            if let view = tileViews[tile.id] {
                view.apply(tile: tile, settings: settings)
            } else if let view = parked.removeValue(forKey: tile.id) {
                view.isHidden = false
                view.apply(tile: tile, settings: settings)
                view.isInteractive = isInteractive
                view.isEditing = isEditing
                view.isPreviewing = isPreviewing
                tileViews[tile.id] = view
                appearing.insert(tile.id)
            } else {
                let view = TileView(tile: tile, settings: settings, context: context)
                view.board = self
                view.isInteractive = isInteractive
                view.isEditing = isEditing
                view.isPreviewing = isPreviewing
                tileViews[tile.id] = view
                addSubview(view)
                appearing.insert(tile.id)
            }
        }
        for (id, view) in tileViews where !seen.contains(id) {
            if parksRemovedTiles {
                view.isHidden = true
                view.isHovering = false
                parked[id] = view
            } else {
                view.tearDown()
                view.removeFromSuperview()
            }
            tileViews[id] = nil
        }

        emptyView.isHidden = !board.tiles.isEmpty
        if !emptyView.isHidden { gallery.update(pointer: nil) }
        layoutTiles(animated: window?.isVisible == true && drag == nil, appearing: appearing)
    }

    private func flushParked() {
        for view in parked.values {
            view.tearDown()
            view.removeFromSuperview()
        }
        parked = [:]
    }

    /// Makes room along the bottom (for the shelf), moving the tiles up.
    func setBottomInset(_ inset: CGFloat, animated: Bool) {
        guard inset != bottomInset else { return }
        bottomInset = inset
        emptyView.frame = canvasFrame
        layoutTiles(animated: animated && window?.isVisible == true && drag == nil, duration: 0.34)
    }

    func tearDown() {
        tileViews.values.forEach { $0.tearDown() }
        flushParked()
    }

    func removeTile(_ id: UUID) {
        context.model.update { $0.removeTile(id, from: boardID) }
    }

    /// Whether the templates are showing, for the self-check.
    var isShowingTemplates: Bool { !emptyView.isHidden }

    var contentViews: [TileContentView] {
        board.tiles.compactMap { tileViews[$0.id]?.content }
    }

    func frame(ofTile id: UUID) -> CGRect? {
        tileViews[id]?.frame
    }

    /// Whether everything inside a tile is the size of the tile, for the self-check.
    func insideMatches(ofTile id: UUID) -> Bool {
        guard let view = tileViews[id] else { return false }
        return view.insideFrames.allSatisfy { inside in
            abs(inside.minX) <= 1 && abs(inside.minY) <= 1
                && abs(inside.width - view.bounds.width) <= 1 && abs(inside.height - view.bounds.height) <= 1
        }
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
        updateGalleryPointer()
    }

    /// Tells the gallery where the pointer is, on an empty board.
    private func updateGalleryPointer() {
        guard !emptyView.isHidden, isInteractive, let window else {
            gallery.update(pointer: nil)
            return
        }
        let point = emptyView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard emptyView.bounds.contains(point) else {
            gallery.update(pointer: nil)
            return
        }
        // SwiftUI measures from the top left.
        gallery.update(pointer: emptyView.isFlipped ? point : CGPoint(x: point.x, y: emptyView.bounds.height - point.y))
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
            height: max(bounds.height - top - padding - bottomInset, 1)
        )
    }

    private var flowOptions: FlowLayout.Options {
        FlowLayout.Options(gap: settings.tileGap.rounded(), minWidth: 180, minHeight: 90)
    }

    private var savedFlowItems: [FlowLayout.Item] {
        board.tiles.map(\.flowItem)
    }

    /// Where every tile belongs, relative to the canvas.
    private func canvasFrames() -> [UUID: LayoutRect] {
        FlowLayout.layout(
            drag?.flowItems ?? savedFlowItems,
            in: LayoutSize(canvasFrame.size),
            options: flowOptions,
            originX: drag?.originX
        )
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

    private func layoutTiles(animated: Bool, duration: Double = 0.18, appearing: Set<UUID> = []) {
        let frames = canvasFrames()
        // A tile being moved follows the pointer, not the layout.
        let floating = drag.flatMap { $0.handle == nil ? $0.tileID : nil }

        // New tiles start where they belong and fade in, rather than growing
        // out of a corner.
        for id in appearing {
            guard let view = tileViews[id], let rect = frames[id] else { continue }
            view.frame = viewFrame(rect)
            view.alphaValue = animated ? 0 : 1
        }

        func place() {
            for (id, view) in tileViews where id != floating {
                guard let rect = frames[id] else { continue }
                let target = viewFrame(rect)
                if view.frame != target {
                    (animated ? view.animator() : view).frame = target
                }
            }
            if animated {
                for id in appearing { tileViews[id]?.animator().alphaValue = 1 }
            }
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = appearing.isEmpty ? duration : max(duration, 0.24)
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
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
        let frames = canvasFrames()
        drag = DragSession(
            tileID: tileView.tileID,
            handle: handle,
            startPointer: convert(event.locationInWindow, from: nil),
            startFrame: start,
            startFrames: frames,
            startItems: savedFlowItems,
            originX: frames.values.map(\.minX).min() ?? 0,
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

        guard let handle = session.handle else {
            // Moving: the tile follows the pointer, and the others make room
            // for wherever it would land.
            session.currentFrame = session.startFrame.offsetBy(dx: delta.x, dy: delta.y)
            tileView.frame = viewFrame(session.currentFrame)
            // A press that hardly moves is not a rearrangement.
            guard abs(delta.x) + abs(delta.y) > 6 else {
                drag = session
                return
            }
            let point = LayoutPoint(x: pointer.x - canvas.minX, y: pointer.y - canvas.minY)
            let items = FlowLayout.dropping(
                session.tileID, at: point, items: session.flowItems, in: size,
                options: flowOptions, originX: session.originX
            )
            let changed = items != session.flowItems
            session.flowItems = items
            drag = session
            if changed { layoutTiles(animated: true) }
            return
        }

        // Resizing, measured from where everything was when the drag began.
        var items = session.startItems
        guard let index = items.firstIndex(where: { $0.id == session.tileID }) else { return }
        // The run of neighbours that make up this tile's column.
        var first = index, last = index
        while first > 0, items[first - 1].column == items[index].column { first -= 1 }
        while last < items.count - 1, items[last + 1].column == items[index].column { last += 1 }

        if handle.movesLeft || handle.movesRight {
            // The row of columns is centred, so an edge moves half as far as
            // the width changes; doubling keeps it under the pointer. The
            // whole column takes the new width.
            let change = handle.movesRight ? 2 * delta.x : -2 * delta.x
            let width = min(max(session.startFrame.width + change, flowOptions.minWidth), size.width)
            for i in first...last { items[i].width = width.rounded() }
        }

        let minHeight = flowOptions.minHeight
        if handle.movesBottom, let start = session.startFrames[session.tileID] {
            // The bottom edge: the top stays put and the tiles below follow.
            let limit = FlowLayout.maxHeight(of: session.tileID, in: items, canvasHeight: size.height, options: flowOptions)
            let wanted = start.height + delta.y
            let othersFill = items[first...last].contains { $0.id != session.tileID && $0.height == nil }
            if index == last, !othersFill, wanted >= limit - 12 {
                // Pulled to the bottom, the bottom tile fills its column again.
                items[index].height = nil
            } else {
                items[index].height = min(max(wanted, minHeight), limit).rounded()
            }
        } else if handle.movesTop, let start = session.startFrames[session.tileID] {
            // The top edge: the bottom stays put. Pulled down, the tile gets
            // shorter and leaves space above it; pushed up, it takes that
            // space back, and then room from the tile above, if there is one.
            let startSpace = session.startItems[index].spaceAbove
            let drop = min(delta.y, start.height - minHeight)
            var space = startSpace + drop
            var height = start.height - drop
            if space < 0 {
                var gained = startSpace
                if index > first, let above = session.startFrames[items[index - 1].id] {
                    let shrunk = max(above.height - (-space), minHeight)
                    gained += above.height - shrunk
                    items[index - 1].height = shrunk.rounded()
                }
                space = 0
                height = start.height + gained
            }
            items[index].spaceAbove = space.rounded()
            items[index].height = height.rounded()
        }
        session.flowItems = items
        drag = session
        layoutTiles(animated: false)
        tileView.setDragging(true, size: tileView.frame.size)
    }

    func endDrag() {
        guard let session = drag else { return }
        drag = nil
        tileViews[session.tileID]?.layer?.zPosition = 0
        tileViews[session.tileID]?.setDragging(false)
        if session.flowItems != session.startItems {
            let items = session.flowItems
            context.model.update { $0.arrangeTiles(items, in: boardID) }
        }
        // Back to a centred row, and covers the case where nothing changed
        // and the model stays quiet.
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
