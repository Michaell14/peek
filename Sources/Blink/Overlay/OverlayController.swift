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

    func shortcutDown() { perform(machine.handle(.shortcutDown(at: now))) }
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
    }

    private func setInteractive(_ interactive: Bool) {
        isInteractive = interactive
        activeBoardView?.isInteractive = interactive
        toolbarHost?.isHidden = !interactive
        brandHost?.isHidden = !interactive
        hoverTimer?.invalidate()
        hoverTimer = nil
        if interactive {
            // Takes keyboard focus without activating the app.
            panel.makeKeyAndOrderFront(nil)
            trackPointer()
        }
    }

    /// Keeps the tile under the pointer showing its controls. The position is
    /// sampled rather than taken from mouse-moved events, which the system
    /// does not reliably send to a window whose app is in the background.
    private func trackPointer() {
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            onMainActor { self?.activeBoardView?.updateHover() }
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
                presentLauncher: { [weak self] in self?.presentLauncher() }
            )
            view = BoardView(board: board, settings: model.settings, context: context)
            boardViews[boardID] = view
            root.boardContainer.addSubview(view)
        }
        // Every board stays in the window so its pages keep loading and
        // refreshing; only the active one is visible.
        for (id, other) in boardViews {
            other.isHidden = id != boardID
        }
        view.topInset = root.topInset
        activeBoardID = boardID
        state.mode = board.mode
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
    }

    private var activeBoardView: BoardView? {
        activeBoardID.flatMap { boardViews[$0] }
    }

    // MARK: - Model changes

    private func workspaceDidChange(_ workspace: Workspace) {
        applySettings(workspace.settings)
        for (id, view) in boardViews {
            if let board = workspace.board(id) {
                view.apply(board: board, settings: workspace.settings)
            } else {
                view.tearDown()
                view.removeFromSuperview()
                boardViews[id] = nil
            }
        }
        if let id = activeBoardID, let board = workspace.board(id) {
            state.mode = board.mode
        }
    }

    private func applySettings(_ settings: AppSettings) {
        machine.tapThreshold = settings.tapThreshold
        root.setBackdrop(opacity: settings.backdropOpacity, blurred: settings.backdropBlur)
        state.shortcutText = settings.shortcut.displayString
        web.configure(for: settings)
    }

    var customFilterError: String? { web.customFilterError }

    func clearBrowsingData(_ data: WebEnvironment.BrowsingData, completion: @escaping @MainActor () -> Void) {
        web.clear(data, completion: completion)
    }

    private func pickerDidChange() {
        state.isPicking = boardViews.values.contains { $0.isPicking }
    }

    // MARK: - Arranging

    func setEditing(_ editing: Bool) {
        if editing { activeBoardView?.stopPicking() }
        state.isEditing = editing
        activeBoardView?.isEditing = editing
    }

    func toggleEditing() {
        setEditing(!state.isEditing)
    }

    // MARK: - Adding content

    func presentLauncher() {
        if !isVisible || !isInteractive { showPinned() }
        setEditing(false)

        let launcher = LauncherModel(searchTemplate: model.settings.searchTemplate)
        launcher.onWebsite = { [weak self] url in self?.addTile(.web(WebContent(url: url))) }
        launcher.onWidget = { [weak self] widget in self?.addTile(.widget(widget)) }
        launcher.onChooseFile = { [weak self] in self?.chooseFiles() }
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
        guard let boardID = activeBoardID, let boardView = boardViews[boardID] else { return }
        let tile = Tile(content: content, frame: boardView.frameForNewTile(content))
        model.update { $0.addTile(tile, to: boardID) }
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
            } else if activeBoardView?.isPicking == true {
                activeBoardView?.stopPicking()
            } else if state.isEditing {
                setEditing(false)
            } else {
                dismiss()
            }
            return true
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
        actions.toggleEditing = { [weak self] in self?.toggleEditing() }
        actions.setMode = { [weak self] mode in self?.setLayoutMode(mode) }
        actions.stopPicking = { [weak self] in self?.activeBoardView?.stopPicking() }
        actions.openSettings = { [weak self] in self?.onOpenSettings?() }

        let host = NSHostingView(rootView: ToolbarView(state: state, actions: actions))
        host.isHidden = true
        toolbarHost = host
        root.setToolbar(host)

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

    func setLayoutMode(_ mode: LayoutMode) {
        activeBoardView?.setMode(mode)
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
            "mode": activeBoardView?.board.mode.rawValue ?? "",
            "launcherOpen": root.isShowingLauncher,
            "tiles": tiles,
        ]
    }
}
