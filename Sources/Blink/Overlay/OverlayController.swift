import AppKit
import Combine
import BlinkCore
import SwiftUI
import UniformTypeIdentifiers

/// Owns the overlay window and decides when it is shown, when it becomes
/// interactive, and which board it displays.
@MainActor
final class OverlayController: NSObject {
    var onOpenSettings: (() -> Void)?

    private(set) var isVisible = false
    private(set) var isInteractive = false
    /// The template most recently kept, and how many have been, so the tour
    /// can tell a template being kept from one being put back.
    private(set) var lastKeptTemplate: BoardTemplate?
    private(set) var templatesKept = 0

    private let model: AppModel
    private let web = WebEnvironment()
    private let panel = OverlayPanel()
    private let root = OverlayRootView()
    private let state = OverlayState()
    private var machine: PeekStateMachine
    private var boardViews: [UUID: BoardView] = [:]
    private var activeBoardID: UUID?
    private var toolbarHost: NSView?
    private var brandHost: NSView?
    private var launcherModel: LauncherModel?
    private var cancellables: Set<AnyCancellable> = []
    private var keyMonitor: Any?
    private var hoverTimer: Timer?
    /// The settings the overlay was last brought in line with.
    private var appliedSettings: AppSettings?
    /// A template being tried on a board, and the tiles to put back if it
    /// is not kept.
    private var preview: (template: BoardTemplate, boardID: UUID, previousTiles: [Tile])?
    private var actions = OverlayActions()
    private var noticeHost: NSView?
    /// The shelf of templates, while it is open.
    private var shelfHost: NSView?
    /// Each template's tiles for as long as the shelf is open, so pointing
    /// back at one brings back the same tiles, pages already loaded.
    private var shelfTiles: [String: [Tile]] = [:]
    /// A template about to go on the board (or nil: the board about to come
    /// back), waiting for the pointer to settle.
    private var shelfPending: (target: String?, work: DispatchWorkItem)?
    private var lastShelfSample: (index: Int?, inside: Bool)?
    /// The board before the last template was kept, for Undo.
    private var lastKept: (boardID: UUID, previous: [Tile])?
    private var keptTimer: Timer?
    /// Bumped on every show and hide so a finishing fade-out can tell whether
    /// the overlay has been reopened in the meantime.
    private var visibilityGeneration = 0

    init(model: AppModel) {
        self.model = model
        machine = PeekStateMachine(tapThreshold: model.settings.tapThreshold)
        super.init()

        panel.contentView = root
        root.onBackgroundClick = { [weak self] in self?.backgroundClicked() }
        installToolbar()

        web.onChange = { [weak self] in
            self?.boardViews.values.forEach { $0.ruleListsDidChange() }
        }
        applySettings(model.settings)

        model.$workspace
            .dropFirst()
            .sink { [weak self] workspace in self?.workspaceDidChange(workspace) }
            .store(in: &cancellables)
        state.objectWillChange
            .sink { [weak self] _ in
                // The toolbar's width follows its contents.
                DispatchQueue.main.async {
                    onMainActor { self?.root.needsLayout = true }
                }
            }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(dismissRequested), name: .blinkDismissOverlay, object: nil)
        center.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    // MARK: - Shortcut

    /// - Parameter elapsed: how long the shortcut had already been down when
    ///   this was called, so a tap is still told apart from a hold.
    func shortcutDown(heldFor elapsed: TimeInterval = 0) {
        perform(machine.handle(.shortcutDown(at: now - max(elapsed, 0))))
    }

    func shortcutUp() { perform(machine.handle(.shortcutUp(at: now))) }
    func shortcutCancelled() { perform(machine.handle(.shortcutCancelled)) }

    /// Opens the overlay and keeps it open.
    func showPinned() { perform(machine.handle(.pin)) }

    func dismiss() { perform(machine.handle(.dismiss)) }

    func toggle() {
        if machine.isVisible {
            dismiss()
        } else {
            showPinned()
        }
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    private func perform(_ effects: [PeekStateMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .show: show()
            case .makeInteractive: setInteractive(true)
            case .hide: hide()
            }
        }
    }

    // MARK: - Showing and hiding

    /// Builds the board for the current display ahead of time, so pages are
    /// already loaded the first time the overlay opens.
    func warmUp() {
        guard !isVisible, let screen = Displays.target(for: model.settings.displayTarget) else { return }
        prepare(for: screen)
    }

    private func show() {
        guard let screen = Displays.target(for: model.settings.displayTarget) else { return }
        prepare(for: screen)
        visibilityGeneration += 1
        let wasVisible = isVisible
        isVisible = true
        activeBoardView?.overlayWillShow()

        if !wasVisible || !panel.isVisible {
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        let duration = model.settings.fadeDuration
        if !wasVisible { zoomBoard(appearing: true, duration: duration) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = 1
        }
        announceChange()
    }

    /// Lets the tour follow along as the overlay comes and goes.
    private func announceChange() {
        NotificationCenter.default.post(name: .blinkOverlayDidChange, object: self)
    }

    /// Tiles settle into place as the overlay appears and ease back as it
    /// goes: a small movement, but it makes the overlay feel like a layer
    /// arriving rather than a picture switching on.
    private func zoomBoard(appearing: Bool, duration: Double) {
        guard duration > 0, let layer = root.boardContainer.layer else { return }
        let bounds = root.boardContainer.bounds
        let scale: CGFloat = 0.985
        // Scale about the centre; a view's layer is anchored at its corner.
        var small = CATransform3DMakeTranslation(bounds.midX, bounds.midY, 0)
        small = CATransform3DScale(small, scale, scale, 1)
        small = CATransform3DTranslate(small, -bounds.midX, -bounds.midY, 0)

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: appearing ? small : CATransform3DIdentity)
        animation.toValue = NSValue(caTransform3D: appearing ? CATransform3DIdentity : small)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "zoom")
    }

    private func hide() {
        guard isVisible else { return }
        isVisible = false
        visibilityGeneration += 1
        let generation = visibilityGeneration

        // Going away without choosing is not choosing.
        closeShelf(animated: false)
        cancelPreview()
        clearKeptNotice()
        closeLauncher()
        setEditing(false)
        setInteractive(false)

        let duration = model.settings.fadeDuration
        zoomBoard(appearing: false, duration: duration)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            onMainActor {
                guard let self, self.visibilityGeneration == generation else { return }
                self.panel.orderOut(nil)
                self.boardViews.values.forEach { $0.overlayDidHide() }
            }
        })
        announceChange()
    }

    private func setInteractive(_ interactive: Bool) {
        isInteractive = interactive
        activeBoardView?.isInteractive = interactive
        toolbarHost?.isHidden = !interactive
        brandHost?.isHidden = !interactive
        noticeHost?.isHidden = !interactive
        hoverTimer?.invalidate()
        hoverTimer = nil
        if interactive {
            // Takes keyboard focus without activating the app.
            panel.makeKeyAndOrderFront(nil)
            trackPointer()
        }
        announceChange()
    }

    /// Keeps the tile under the pointer showing its controls. The position is
    /// sampled rather than taken from mouse-moved events, which the system
    /// does not reliably send to a window whose app is in the background.
    private func trackPointer() {
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            onMainActor {
                self?.activeBoardView?.updateHover()
                self?.updateShelfPointer()
            }
        }
        timer.tolerance = 0.03
        // .common, so it keeps running while a menu or a drag is tracking.
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func prepare(for screen: NSScreen) {
        let boardID = model.boardID(forDisplay: screen.displayKey, name: screen.localizedName)
        if panel.frame != screen.frame {
            panel.setFrame(screen.frame, display: false)
            root.needsLayout = true
        }
        root.topInset = max(screen.menuBarHeight, Theme.minimumTopInset)
        activate(boardID)
    }

    private func activate(_ boardID: UUID) {
        guard let board = model.workspace.board(boardID) else { return }
        let view: BoardView
        if let existing = boardViews[boardID] {
            view = existing
        } else {
            let context = TileContext(
                model: model,
                boardID: boardID,
                web: web,
                pickerDidChange: { [weak self] in self?.pickerDidChange() },
                presentLauncher: { [weak self] in self?.presentLauncher() },
                useTemplate: { [weak self] template in self?.applyTemplate(template) }
            )
            view = BoardView(board: board, settings: model.settings, context: context)
            boardViews[boardID] = view
            root.boardContainer.addSubview(view)
            root.needsLayout = true
        }
        // Every board stays in the window so its pages keep loading and
        // refreshing; only the active one is visible.
        if boardID != activeBoardID {
            for (id, other) in boardViews {
                other.isHidden = id != boardID
            }
            activeBoardID = boardID
            root.needsLayout = true
        }
        view.topInset = root.topInset
        // Showing the same board again finds nothing to lay out: this is on
        // the way to every peek, so it should cost next to nothing.
        root.layoutSubtreeIfNeeded()
    }

    private var activeBoardView: BoardView? {
        activeBoardID.flatMap { boardViews[$0] }
    }

    // MARK: - Model changes

    /// Brings the boards in line with the model. A change usually touches
    /// one tile on one board (typing in a note saves on every keystroke), so
    /// only boards that differ, or all of them when settings changed, are
    /// visited.
    private func workspaceDidChange(_ workspace: Workspace) {
        let settingsChanged = workspace.settings != appliedSettings
        if settingsChanged { applySettings(workspace.settings) }
        for (id, view) in boardViews {
            if let board = workspace.board(id) {
                if settingsChanged || board != view.board {
                    view.apply(board: board, settings: workspace.settings)
                }
            } else {
                view.tearDown()
                view.removeFromSuperview()
                boardViews[id] = nil
                if activeBoardID == id { activeBoardID = nil }
            }
        }
    }

    private func applySettings(_ settings: AppSettings) {
        appliedSettings = settings
        machine.tapThreshold = settings.tapThreshold
        root.setBackdrop(opacity: settings.backdropOpacity, blurred: settings.backdropBlur)
        let shortcutText = settings.shortcut.displayString
        if state.shortcutText != shortcutText { state.shortcutText = shortcutText }
        web.configure(for: settings)
    }

    var customFilterError: String? { web.customFilterError }

    func clearBrowsingData(_ data: WebEnvironment.BrowsingData, completion: @escaping @MainActor () -> Void) {
        web.clear(data, completion: completion)
    }

    private func pickerDidChange() {
        let isPicking = boardViews.values.contains { $0.isPicking }
        if state.isPicking != isPicking { state.isPicking = isPicking }
    }

    // MARK: - Arranging

    func setEditing(_ editing: Bool) {
        if editing {
            closeShelf()
            activeBoardView?.stopPicking()
            // Arranging a template is keeping it.
            keepPreview()
        }
        // Every hide passes through here. An unchanged value must not wake
        // the toolbar, which would lay itself out again for nothing.
        if state.isEditing != editing { state.isEditing = editing }
        activeBoardView?.isEditing = editing
    }

    func toggleEditing() {
        setEditing(!state.isEditing)
    }

    // MARK: - Adding content

    func presentLauncher() {
        presentLauncher(scope: nil)
    }

    /// The palette, with only templates in it.
    /// The Templates button: the shelf along the bottom.
    func presentTemplates() {
        openShelf()
    }

    private func presentLauncher(scope: LauncherModel.Item.Kind?) {
        if !isVisible || !isInteractive { showPinned() }
        setEditing(false)
        closeShelf()
        closeLauncher()

        let launcher = LauncherModel(searchTemplate: model.settings.searchTemplate, scope: scope)
        launcher.onWebsite = { [weak self] url in self?.addTile(.web(WebContent(url: url))) }
        launcher.onWidget = { [weak self] widget in self?.addTile(.widget(widget)) }
        launcher.onChooseFile = { [weak self] in self?.chooseFiles() }
        launcher.onTemplate = { [weak self] template in self?.previewTemplate(template) }
        launcherModel = launcher

        let host = NSHostingView(rootView: LauncherView(model: launcher))
        host.sizingOptions = []
        root.setLauncher(host)
        panel.makeFirstResponder(host)
    }

    func closeLauncher() {
        guard root.isShowingLauncher else { return }
        launcherModel = nil
        root.setLauncher(nil)
    }

    func addTile(_ content: TileContent) {
        if !isVisible { showPinned() }
        closeLauncher()
        keepPreview()
        guard let boardID = activeBoardID, boardViews[boardID] != nil else { return }
        model.update { $0.addTile(Tile(content: content), to: boardID) }
    }

    // MARK: - Trying templates

    /// Puts a template on the board on screen to try, with the person's own
    /// calendar, messages and pages in it. The toolbar then offers to keep
    /// it, to flip to the next template, or to put the board back as it was.
    func previewTemplate(_ template: BoardTemplate) {
        if !isVisible || !isInteractive { showPinned() }
        closeLauncher()
        setEditing(false)
        guard let boardID = activeBoardID, let board = model.workspace.board(boardID) else { return }
        // Flipping between templates still goes back to what was there first.
        let previous = preview?.boardID == boardID ? preview?.previousTiles ?? board.tiles : board.tiles
        preview = (template, boardID, previous)
        let tiles: [Tile]
        if state.isShelfOpen {
            tiles = shelfTiles[template.id] ?? template.makeTiles()
            shelfTiles[template.id] = tiles
        } else {
            tiles = template.makeTiles()
        }
        // The board's own tiles are set aside, not torn down, until the
        // template is kept: putting them back is then instant.
        boardViews[boardID]?.parksRemovedTiles = true
        boardViews[boardID]?.isPreviewing = true
        model.update { workspace in
            workspace.updateBoard(boardID) { $0.tiles = tiles }
        }
        let all = BoardTemplate.all
        let index = all.firstIndex { $0.id == template.id } ?? 0
        state.previewName = template.name
        state.previewPosition = "\(index + 1) of \(all.count)"
        announceChange()
    }

    /// The template on the board being tried, if one is.
    var previewingTemplate: BoardTemplate? { preview?.template }

    /// The template before or after the one being tried.
    func stepPreview(by offset: Int) {
        guard let current = preview?.template else { return }
        let all = BoardTemplate.all
        guard let index = all.firstIndex(where: { $0.id == current.id }) else { return }
        previewTemplate(all[(index + offset + all.count) % all.count])
    }

    /// Keeps the template being tried.
    func keepPreview() {
        guard let preview else { return }
        self.preview = nil
        state.previewName = nil
        lastKeptTemplate = preview.template
        templatesKept += 1
        stopTrying(on: preview.boardID)
        lastKept = (preview.boardID, preview.previousTiles)
        showKeptNotice(preview.template.name)
        announceChange()
    }

    /// Puts the board back as it was before trying templates.
    func cancelPreview() {
        guard let preview else { return }
        self.preview = nil
        state.previewName = nil
        model.update { workspace in
            workspace.updateBoard(preview.boardID) { $0.tiles = preview.previousTiles }
        }
        stopTrying(on: preview.boardID)
        announceChange()
    }

    private func stopTrying(on boardID: UUID) {
        boardViews[boardID]?.isPreviewing = false
        // With the shelf open, the tiles set aside may yet be pointed at again.
        if !state.isShelfOpen { boardViews[boardID]?.parksRemovedTiles = false }
    }

    // MARK: - Undo

    private func showKeptNotice(_ name: String) {
        state.keptName = name
        keptTimer?.invalidate()
        keptTimer = Timer.scheduledTimer(withTimeInterval: 7, repeats: false) { [weak self] _ in
            onMainActor { self?.clearKeptNotice() }
        }
    }

    private func clearKeptNotice() {
        keptTimer?.invalidate()
        keptTimer = nil
        if state.keptName != nil { state.keptName = nil }
        lastKept = nil
    }

    /// Puts the board back as it was before the last template was kept.
    func undoTemplate() {
        guard let lastKept else { return }
        clearKeptNotice()
        model.update { workspace in
            workspace.updateBoard(lastKept.boardID) { $0.tiles = lastKept.previous }
        }
    }

    // MARK: - The shelf of templates

    func openShelf() {
        if !isVisible || !isInteractive { showPinned() }
        closeLauncher()
        setEditing(false)
        if preview != nil { cancelPreview() }
        guard shelfHost == nil, let board = activeBoardView else { return }
        shelfTiles = [:]
        lastShelfSample = nil
        state.shelfPointed = nil
        state.shelfShowing = nil
        state.isShelfOpen = true

        let host = NSHostingView(rootView: TemplateShelf(state: state, actions: actions))
        host.sizingOptions = []
        shelfHost = host
        root.setShelf(host)
        let frame = root.shelfFrame
        host.frame = frame.offsetBy(dx: 0, dy: 28)
        host.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.34
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            host.animator().frame = frame
            host.animator().alphaValue = 1
        }

        // The board moves up to make room, so all of it shows above the shelf.
        board.parksRemovedTiles = true
        let padding = CGFloat(model.settings.canvasPadding.rounded())
        board.setBottomInset(max(root.bounds.height - frame.minY + 10 - padding, 0), animated: true)
        announceChange()
    }

    func closeShelf(animated: Bool = true) {
        guard let host = shelfHost else { return }
        shelfPending?.work.cancel()
        shelfPending = nil
        if preview != nil { cancelPreview() }
        shelfHost = nil
        state.isShelfOpen = false
        state.shelfPointed = nil
        state.shelfShowing = nil
        shelfTiles = [:]
        for board in boardViews.values {
            board.parksRemovedTiles = false
            board.setBottomInset(0, animated: animated)
        }
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                host.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                onMainActor {
                    guard let self, self.root.shelf === host else { return }
                    self.root.setShelf(nil)
                }
            })
        } else {
            root.setShelf(nil)
        }
        announceChange()
    }

    /// Keeps a template from the shelf and puts the shelf away.
    func chooseFromShelf(_ template: BoardTemplate) {
        shelfPending?.work.cancel()
        shelfPending = nil
        if preview?.template.id != template.id { previewTemplate(template) }
        keepPreview()
        closeShelf()
    }

    /// Where the pointer is over the shelf, sampled with the tiles' hover.
    private func updateShelfPointer() {
        guard let host = shelfHost, state.isShelfOpen else { return }
        let point = host.convert(panel.mouseLocationOutsideOfEventStream, from: nil)
        let inside = host.bounds.contains(point)
        let local = host.isFlipped ? point : CGPoint(x: point.x, y: host.bounds.height - point.y)
        let index = inside ? TemplateShelf.card(at: local, width: host.bounds.width) : nil
        // Only a change counts, so a template chosen with the arrow keys
        // stays until the pointer moves somewhere new.
        if let last = lastShelfSample, last.index == index, last.inside == inside { return }
        lastShelfSample = (index, inside)
        pointShelf(at: index, insideShelf: inside)
    }

    /// The pointer is over a card (or between cards, or off the shelf). A
    /// template goes on the board once the pointer rests on it, so a sweep
    /// across the shelf does not flicker; leaving the shelf puts the board back.
    func pointShelf(at index: Int?, insideShelf: Bool) {
        guard state.isShelfOpen else { return }
        let pointed = index.flatMap { BoardTemplate.all.indices.contains($0) ? BoardTemplate.all[$0].id : nil }
        if state.shelfPointed != pointed { state.shelfPointed = pointed }
        if pointed == nil, insideShelf {
            // Between cards, or on the shelf's heading, nothing changes.
            shelfPending?.work.cancel()
            shelfPending = nil
            return
        }
        // Off the shelf, the target is nil: the board as it was.
        let target = pointed
        if target == state.shelfShowing {
            shelfPending?.work.cancel()
            shelfPending = nil
            return
        }
        if let pending = shelfPending, pending.target == target { return }
        shelfPending?.work.cancel()
        let work = DispatchWorkItem { [weak self] in
            onMainActor { self?.showOnShelf(target) }
        }
        shelfPending = (target, work)
        DispatchQueue.main.asyncAfter(deadline: .now() + (target == nil ? 0.22 : 0.12), execute: work)
    }

    private func showOnShelf(_ id: String?) {
        shelfPending = nil
        guard state.isShelfOpen else { return }
        if let id, let template = BoardTemplate.all.first(where: { $0.id == id }) {
            previewTemplate(template)
            state.shelfShowing = id
        } else {
            cancelPreview()
            state.shelfShowing = nil
        }
    }

    private func stepShelf(by offset: Int) {
        let all = BoardTemplate.all
        let next: Int
        if let current = all.firstIndex(where: { $0.id == state.shelfShowing }) {
            next = (current + offset + all.count) % all.count
        } else {
            next = offset > 0 ? 0 : all.count - 1
        }
        shelfPending?.work.cancel()
        shelfPending = nil
        showOnShelf(all[next].id)
    }

    /// Whether the bar for trying templates is out of the way (while the
    /// tour shows its own cards for choosing).
    var hidesPreviewBar: Bool {
        get { state.hidesPreviewBar }
        set { if state.hidesPreviewBar != newValue { state.hidesPreviewBar = newValue } }
    }

    var panelFrame: CGRect { panel.frame }

    /// Keeps the bottom of the board clear by this much, measured from the
    /// bottom of the screen, for something sitting over it (the tour).
    func setBottomRoom(_ points: CGFloat) {
        guard !state.isShelfOpen else { return }
        let padding = CGFloat(model.settings.canvasPadding.rounded())
        activeBoardView?.setBottomInset(points > 0 ? max(points - padding, 0) : 0, animated: true)
    }

    /// For the self-check: as if the pointer rested on a card of an empty
    /// board's gallery.
    func pointGallery(at id: String?) {
        activeBoardView?.gallery.point(at: id)
    }

    /// Fills the board on screen with a template, without trying it first.
    func applyTemplate(_ template: BoardTemplate) {
        previewTemplate(template)
        keepPreview()
    }

    /// Adds local PDF and HTML files; anything else is ignored.
    func addFiles(_ urls: [URL]) {
        for url in urls {
            if let file = FileContent(path: url.path) {
                addTile(.file(file))
            }
        }
    }

    private func chooseFiles() {
        // The file dialog is an ordinary window and would open behind the
        // overlay, so step aside while it is up.
        dismiss()
        let dialog = NSOpenPanel()
        dialog.allowedContentTypes = [.pdf, .html]
        dialog.allowsMultipleSelection = true
        dialog.message = "Choose PDF or HTML files to add to Blink"
        NSApp.activate(ignoringOtherApps: true)
        let response = dialog.runModal()
        showPinned()
        if response == .OK {
            addFiles(dialog.urls)
        }
    }

    // MARK: - Input

    private func backgroundClicked() {
        if root.isShowingLauncher {
            closeLauncher()
        } else if isInteractive, !state.isEditing {
            dismiss()
        }
    }

    /// Returns true when the key press was handled here.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard isVisible, event.window === panel else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

        if event.keyCode == 53, flags.isEmpty {
            // Escape backs out one step at a time.
            if root.isShowingLauncher {
                closeLauncher()
            } else if state.isShelfOpen {
                closeShelf()
            } else if preview != nil {
                cancelPreview()
            } else if activeBoardView?.isPicking == true {
                activeBoardView?.stopPicking()
            } else if state.isEditing {
                setEditing(false)
            } else {
                dismiss()
            }
            return true
        }

        // With the shelf open, the arrow keys go along it and Return keeps
        // the template on the board.
        if state.isShelfOpen, !root.isShowingLauncher, flags.isEmpty {
            switch event.keyCode {
            case 123:
                stepShelf(by: -1)
                return true
            case 124:
                stepShelf(by: 1)
                return true
            case 36, 76:
                if let template = preview?.template { chooseFromShelf(template) }
                return true
            default:
                break
            }
        }

        // While a template is being tried: the arrow keys flip between
        // templates and Return keeps the one on the board.
        if preview != nil, !root.isShowingLauncher, flags.isEmpty {
            switch event.keyCode {
            case 123:
                stepPreview(by: -1)
                return true
            case 124:
                stepPreview(by: 1)
                return true
            case 36, 76:
                keepPreview()
                return true
            default:
                break
            }
        }

        // With the launcher open, the arrow keys and Return drive its list
        // while typing goes to its text field.
        if let launcherModel, root.isShowingLauncher, flags.isEmpty {
            switch event.keyCode {
            case 125:
                launcherModel.moveSelection(by: 1)
                return true
            case 126:
                launcherModel.moveSelection(by: -1)
                return true
            case 36, 76:
                launcherModel.activateSelection()
                return true
            default:
                break
            }
        }

        guard isInteractive, flags == .command,
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch key {
        case "e":
            toggleEditing()
        case "n", "t":
            presentLauncher()
        case ",":
            onOpenSettings?()
        case "w":
            dismiss()
        case "r":
            guard let tile = activeBoardView?.webTileUnderPointer() else { return false }
            tile.reload()
        case "[":
            guard let tile = activeBoardView?.webTileUnderPointer() else { return false }
            tile.goBack()
        case "]":
            guard let tile = activeBoardView?.webTileUnderPointer() else { return false }
            tile.goForward()
        default:
            return false
        }
        return true
    }

    @objc private func dismissRequested() {
        dismiss()
    }

    @objc private func screensChanged() {
        guard isVisible, let screen = Displays.target(for: model.settings.displayTarget) else { return }
        prepare(for: screen)
    }

    // MARK: - Toolbar

    private func installToolbar() {
        var actions = OverlayActions()
        actions.add = { [weak self] in self?.presentLauncher() }
        actions.templates = { [weak self] in self?.presentTemplates() }
        actions.previewStep = { [weak self] offset in self?.stepPreview(by: offset) }
        actions.keepPreview = { [weak self] in self?.keepPreview() }
        actions.cancelPreview = { [weak self] in self?.cancelPreview() }
        actions.chooseFromShelf = { [weak self] template in self?.chooseFromShelf(template) }
        actions.closeShelf = { [weak self] in self?.closeShelf() }
        actions.undoTemplate = { [weak self] in self?.undoTemplate() }
        actions.toggleEditing = { [weak self] in self?.toggleEditing() }
        actions.stopPicking = { [weak self] in self?.activeBoardView?.stopPicking() }
        actions.openSettings = { [weak self] in self?.onOpenSettings?() }

        self.actions = actions
        let host = NSHostingView(rootView: ToolbarView(state: state, actions: actions))
        host.isHidden = true
        toolbarHost = host
        root.setToolbar(host)

        let notice = NSHostingView(rootView: KeptNoticeView(state: state) { [weak self] in self?.undoTemplate() })
        notice.isHidden = true
        noticeHost = notice
        root.setNotice(notice)

        let brand = PassthroughHostingView(rootView: BrandView(state: state))
        brand.isHidden = true
        brandHost = brand
        root.setBrand(brand)
    }

    // MARK: - Self-check support

    var ruleListCount: Int { web.ruleLists.count }

    var firstWebTile: WebTileContentView? {
        activeBoardView?.contentViews.lazy.compactMap { $0 as? WebTileContentView }.first
    }

    /// A description of what is on screen, for the automated self-check.
    func snapshot() -> [String: Any] {
        var tiles: [[String: Any]] = []
        if let boardView = activeBoardView {
            for tile in boardView.board.tiles {
                let frame = boardView.frame(ofTile: tile.id) ?? .zero
                let kind: String
                switch tile.content {
                case .web: kind = "web"
                case .file: kind = "file"
                case .widget(let widget): kind = "widget:" + widget.displayName.lowercased()
                }
                var entry: [String: Any] = [
                    "id": tile.id.uuidString,
                    "kind": kind,
                    "frame": [frame.minX, frame.minY, frame.width, frame.height].map { Double($0) },
                    "insideMatches": boardView.insideMatches(ofTile: tile.id),
                ]
                if let controls = boardView.controlsFrame(ofTile: tile.id) {
                    entry["controls"] = [controls.minX, controls.minY, controls.width, controls.height].map { Double($0) }
                }
                tiles.append(entry)
            }
        }
        return [
            "visible": isVisible,
            "interactive": isInteractive,
            "editing": state.isEditing,
            "panelOnScreen": panel.isVisible,
            "panelIsKey": panel.isKeyWindow,
            "panelAlpha": Double(panel.alphaValue),
            "panelFrame": [panel.frame.minX, panel.frame.minY, panel.frame.width, panel.frame.height].map { Double($0) },
            "panelLevel": panel.level.rawValue,
            "windowNumber": panel.windowNumber,
            "launcherOpen": root.isShowingLauncher,
            "templatesShown": activeBoardView?.isShowingTemplates ?? false,
            "previewing": state.previewName ?? "",
            "shelfOpen": state.isShelfOpen,
            "shelfShowing": state.shelfShowing ?? "",
            "shelfFrame": shelfHost.map { _ in [root.shelfFrame.minX, root.shelfFrame.minY, root.shelfFrame.width, root.shelfFrame.height].map { Double($0) } } ?? [],
            "keptNotice": state.keptName ?? "",
            "previewBarHidden": state.hidesPreviewBar,
            "galleryHot": activeBoardView?.gallery.hot ?? "",
            "tiles": tiles,
        ]
    }
}
