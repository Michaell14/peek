import AppKit
import BlinkCore
import Combine
import EventKit
import SwiftUI

/// The tour: seven short steps, most of them done with the real overlay
/// rather than read about. It follows the overlay as it comes and goes, so
/// holding and tapping the real keys is what moves it along.
@MainActor
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case hello, hold, tap, shortcut, board, access, ready

        /// Steps drawn as a small coach along the bottom of the screen, above
        /// the overlay, so it can be watched while the keys are down.
        var isCoach: Bool { self == .hold || self == .tap || self == .board }

        /// "Step n of 4" covers the four things there are to learn.
        var number: Int? {
            switch self {
            case .hold: return 1
            case .tap: return 2
            case .shortcut: return 3
            case .board: return 4
            default: return nil
            }
        }
    }

    enum ShortcutChoice: Equatable {
        case standard, function, custom
    }

    static let doneKey = "OnboardingDone"

    @Published private(set) var step: Step = .hello

    // Holding.
    @Published private(set) var isPeeking = false
    @Published private(set) var peeks = 0
    @Published private(set) var tappedInstead = false

    // Tapping.
    @Published private(set) var isPinned = false
    @Published private(set) var openedPinned = false
    @Published private(set) var closedAfterPin = false

    // The starting board.
    @Published private(set) var trying: BoardTemplate?
    @Published private(set) var kept: BoardTemplate?
    @Published private(set) var putBack = false

    // The shortcut.
    @Published private(set) var shortcutChoice: ShortcutChoice = .standard

    /// How tall each step's content is, as laid out; the window follows.
    @Published var contentHeights: [Int: CGFloat] = [:]

    // Access.
    @Published var opensAtLogin = true
    @Published private(set) var loginProblem: String?

    let model: AppModel
    let overlay: OverlayController
    let hotkeys: HotkeyMonitor

    /// Called when the tour is finished or skipped; true when the person
    /// went all the way through.
    var onFinish: ((Bool) -> Void)?

    private var last = (visible: false, interactive: false)
    private var keptBaseline = 0
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel, overlay: OverlayController, hotkeys: HotkeyMonitor) {
        self.model = model
        self.overlay = overlay
        self.hotkeys = hotkeys
        NotificationCenter.default.publisher(for: .blinkOverlayDidChange)
            .sink { [weak self] _ in onMainActor { self?.overlayChanged() } }
            .store(in: &cancellables)
    }

    static var isDone: Bool {
        get { UserDefaults.standard.bool(forKey: doneKey) }
        set { UserDefaults.standard.set(newValue, forKey: doneKey) }
    }

    /// The shortcut as the keys to press, one cap each.
    var caps: [OnboardingKey] { OnboardingKey.caps(for: model.settings.shortcut) }

    var shortcutText: String { model.settings.shortcut.displayString }

    // MARK: - Moving through

    func restart() {
        peeks = 0
        tappedInstead = false
        openedPinned = false
        closedAfterPin = false
        kept = nil
        putBack = false
        shortcutChoice = Self.choice(for: model.settings.shortcut)
        // On a first run, opening at login is offered switched on.
        opensAtLogin = Self.isDone ? LoginItem.isEnabled : true
        loginProblem = nil
        go(to: .hello)
    }

    func go(to next: Step) {
        // Leaving the board step with a template still on trial puts the
        // board back; anything kept stays.
        if step == .board, next != .board, overlay.isVisible { overlay.dismiss() }
        if next == .shortcut { shortcutChoice = Self.choice(for: model.settings.shortcut) }
        last = (overlay.isVisible, overlay.isInteractive)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            step = next
        }
        if next == .board { startTrying() }
    }

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            finish(completed: true)
            return
        }
        go(to: next)
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        go(to: previous)
    }

    /// Leaves the tour now. It is not shown again on its own.
    func skipTour() {
        finish(completed: false)
    }

    private func finish(completed: Bool) {
        if overlay.isVisible, step == .board { overlay.dismiss() }
        Self.isDone = true
        onFinish?(completed)
    }

    // MARK: - Following the overlay

    private func overlayChanged() {
        let now = (visible: overlay.isVisible, interactive: overlay.isInteractive)
        defer { last = now }
        let wentAway = last.visible && !now.visible

        switch step {
        case .hold:
            isPeeking = now.visible && !now.interactive
            if now.interactive, !last.interactive { tappedInstead = true }
            if wentAway, !last.interactive {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.7)) {
                    peeks += 1
                    tappedInstead = false
                }
            }
        case .tap:
            isPeeking = now.visible && !now.interactive
            isPinned = now.visible && now.interactive
            withAnimation(.spring(response: 0.36, dampingFraction: 0.7)) {
                if now.interactive, !last.interactive { openedPinned = true }
                if wentAway, last.interactive, openedPinned { closedAfterPin = true }
            }
        case .board:
            let wasTrying = trying != nil
            trying = overlay.previewingTemplate
            withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                if overlay.templatesKept > keptBaseline {
                    kept = overlay.lastKeptTemplate
                    putBack = false
                } else if wasTrying, trying == nil {
                    putBack = true
                }
            }
        default:
            isPeeking = false
            isPinned = false
        }
    }

    // MARK: - The starting board

    func startTrying(_ template: BoardTemplate? = nil) {
        keptBaseline = overlay.templatesKept
        kept = nil
        putBack = false
        overlay.previewTemplate(template ?? trying ?? BoardTemplate.all[0])
        trying = overlay.previewingTemplate
    }

    func keepTrying() {
        overlay.keepPreview()
    }

    // MARK: - The shortcut

    static func choice(for shortcut: Shortcut) -> ShortcutChoice {
        switch shortcut {
        case .default: return .standard
        case .functionKey: return .function
        default: return .custom
        }
    }

    func choose(_ choice: ShortcutChoice) {
        shortcutChoice = choice
        switch choice {
        case .standard:
            model.updateSettings { $0.shortcut = .default }
        case .function:
            model.updateSettings { $0.shortcut = .functionKey }
        case .custom:
            break
        }
    }

    // MARK: - Access

    func applyLoginChoice() {
        guard opensAtLogin != LoginItem.isEnabled else { return }
        loginProblem = LoginItem.setEnabled(opensAtLogin)
    }
}

/// One key of the shortcut, as drawn on a key cap.
struct OnboardingKey: Hashable {
    /// The symbol or character on the cap.
    var symbol: String
    /// The word under it, for modifier keys.
    var name: String?

    static func caps(for shortcut: Shortcut) -> [OnboardingKey] {
        var caps = shortcut.modifiers.map { key -> OnboardingKey in
            let word: String
            switch key.modifier {
            case .control: word = "control"
            case .option: word = "option"
            case .shift: word = "shift"
            case .command: word = "command"
            case .function: return OnboardingKey(symbol: "fn", name: nil)
            }
            switch key.side {
            case .any: return OnboardingKey(symbol: key.modifier.symbol, name: word)
            case .left: return OnboardingKey(symbol: key.modifier.symbol, name: "left \(word)")
            case .right: return OnboardingKey(symbol: key.modifier.symbol, name: "right \(word)")
            }
        }
        if let keyCode = shortcut.keyCode {
            caps.append(OnboardingKey(symbol: KeyNames.name(for: keyCode), name: nil))
        }
        return caps
    }
}

// MARK: - The window

/// Puts the tour on screen: a floating card in the middle for the steps
/// that are read, and a coach along the bottom, above the overlay, for the
/// steps that are done with the real keys.
@MainActor
final class OnboardingController {
    let tour: OnboardingModel
    private var window: OnboardingWindow?
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel, overlay: OverlayController, hotkeys: HotkeyMonitor) {
        tour = OnboardingModel(model: model, overlay: overlay, hotkeys: hotkeys)
        tour.onFinish = { [weak self] completed in self?.close(thenShowBoard: completed) }
        // The window takes the size of whatever the step shows, once it has
        // been laid out: on a new step, and when a step grows or shrinks.
        tour.$step
            .combineLatest(tour.$contentHeights)
            .dropFirst()
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] step, _ in
                onMainActor { self?.place(for: step, animated: true) }
            }
            .store(in: &cancellables)
    }

    var isShowing: Bool { window?.isVisible == true }

    var windowFrame: CGRect? { window?.frame }

    var windowLevel: Int { window?.level.rawValue ?? 0 }

    func show() {
        tour.overlay.dismiss()
        tour.restart()
        if window == nil {
            let window = OnboardingWindow()
            let host = NSHostingView(rootView: OnboardingView(tour: tour, model: tour.model, hotkeys: tour.hotkeys))
            // The window's size is the tour's to set, step by step.
            host.sizingOptions = []
            window.setContent(host)
            self.window = window
        }
        place(for: tour.step, animated: false)
        window?.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            window?.animator().alphaValue = 1
        }
    }

    private func close(thenShowBoard showsBoard: Bool) {
        guard let window else { return }
        let start = window.frame
        // The card shrinks into the command bar as the board arrives.
        let screen = window.screen?.frame ?? start
        let end = CGRect(x: screen.midX - 60, y: screen.maxY - 44, width: 120, height: 30)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = showsBoard ? 0.42 : 0.25
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            if showsBoard { window.animator().setFrame(end, display: true) }
            window.animator().alphaValue = 0
        }, completionHandler: {
            onMainActor {
                window.orderOut(nil)
                window.setFrame(start, display: false)
            }
        })
        if showsBoard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                onMainActor { self?.tour.overlay.showPinned() }
            }
        }
    }

    /// Sizes the window to the step and moves it where that step belongs.
    private func place(for step: OnboardingModel.Step, animated: Bool) {
        guard let window,
              let screen = Displays.target(for: tour.model.settings.displayTarget) ?? NSScreen.main else { return }
        let measured = tour.contentHeights[step.rawValue] ?? 0
        let size = CGSize(
            width: OnboardingView.width(for: step),
            height: measured > 40 ? measured : OnboardingView.estimatedHeight(for: step)
        )
        let visible = screen.visibleFrame
        let origin: CGPoint
        if step.isCoach {
            origin = CGPoint(x: visible.midX - size.width / 2, y: screen.frame.minY + (step == .board ? 22 : 64))
        } else {
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height * 0.04)
        }
        // The coach sits above the overlay, which sits above everything else.
        // The other steps stay ordinary windows, so System Settings and the
        // permission prompts they lead to can come up in front.
        window.level = step.isCoach ? NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2) : .normal
        let frame = CGRect(origin: origin, size: size).integral
        guard frame != window.frame else { return }
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.45
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                window.animator().setFrame(frame, display: true)
            }, completionHandler: {
                onMainActor { window.invalidateShadow() }
            })
        } else {
            window.setFrame(frame, display: true)
            window.invalidateShadow()
        }
        if step.isCoach == false { window.makeKey() }
    }
}

/// A borderless, rounded window of glass that can still take the keyboard.
final class OnboardingWindow: NSWindow {
    private let glass = NSVisualEffectView()

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 520, height: 480), styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        appearance = NSAppearance(named: .darkAqua)
        title = "Blink Tour"

        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.maskImage = NSImage.roundedMask(radius: 22)
        glass.autoresizingMask = [.width, .height]
        contentView = glass
    }

    func setContent(_ view: NSView) {
        view.frame = glass.bounds
        view.autoresizingMask = [.width, .height]
        glass.addSubview(view)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        // esc is the overlay's; here it does nothing rather than beep.
    }
}
