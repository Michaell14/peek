import AppKit
import BlinkCore
import WebKit

/// The window a pop-up lives in. It takes the keyboard without bringing
/// Blink forward, like the overlay, so typing a password works over a
/// full-screen app.
final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.type == .keyDown, flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return EditingShortcuts.perform(event, from: self)
    }
}

/// A window a page in a tile opened for itself, usually to sign in ("Sign in
/// with Google"). It shares the opening page's cookies and stays linked to
/// it, so the page hears back when signing in is done, and it closes when
/// the page closes it, as a browser's pop-up does. It belongs to the overlay:
/// it goes when the overlay goes and comes back with it.
@MainActor
final class PopupWindow: NSObject {
    let webView: WKWebView
    let panel: PopupPanel
    private weak var parent: NSWindow?
    private var observations: [NSKeyValueObservation] = []
    private var onClose: ((PopupWindow) -> Void)?

    /// - Parameters:
    ///   - configuration: the one WebKit handed over for the new window. It
    ///     must be used as is, or the page loses its link to the pop-up.
    ///   - anchor: the opening tile, in screen coordinates; the pop-up is
    ///     centred on it.
    init(
        configuration: WKWebViewConfiguration,
        features: WKWindowFeatures,
        userAgent: String?,
        appearance: NSAppearance?,
        over parent: NSWindow,
        centeredOn anchor: NSRect,
        onClose: @escaping (PopupWindow) -> Void
    ) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = userAgent
        webView.appearance = appearance
        webView.isInspectable = true

        let visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = PopupSizing.size(
            requestedWidth: features.width?.doubleValue,
            requestedHeight: features.height?.doubleValue,
            screenWidth: visible.width,
            screenHeight: visible.height
        )
        let contentRect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        panel = PopupPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.parent = parent
        self.onClose = onClose
        super.init()

        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.contentView = webView
        webView.uiDelegate = self
        webView.navigationDelegate = self

        var frame = panel.frameRect(forContentRect: contentRect)
        frame.origin = NSPoint(x: anchor.midX - frame.width / 2, y: anchor.midY - frame.height / 2)
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        panel.setFrame(frame, display: false)

        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] _, _ in
                onMainActor { self?.updateTitle() }
            },
            webView.observe(\.title, options: [.new]) { [weak self] _, _ in
                onMainActor { self?.updateTitle() }
            },
        ]
        show(focus: true)
    }

    /// Shows it above the overlay, optionally with the keyboard.
    func show(focus: Bool) {
        guard let parent else { return }
        // Ordering a child window out detaches it, so attach it each time.
        if panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
        panel.level = NSWindow.Level(rawValue: parent.level.rawValue + 1)
        if focus {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFront(nil)
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    func close() {
        panel.close()
    }

    /// Runs a script in the pop-up's page, for the self-check.
    func evaluate(_ script: String) async -> String {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(returning: "error: \(error.localizedDescription)")
                } else {
                    continuation.resume(returning: value.map { String(describing: $0) } ?? "")
                }
            }
        }
    }

    /// The site comes first, so it is clear who is asking for a password.
    private func updateTitle() {
        if let url = webView.url, url.isFileURL || url.scheme?.hasPrefix("http") == true {
            panel.title = URLInput.displayHost(for: url)
        }
        panel.subtitle = webView.title ?? ""
    }
}

// MARK: - NSWindowDelegate

extension PopupWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        observations.removeAll()
        webView.stopLoading()
        webView.uiDelegate = nil
        webView.navigationDelegate = nil
        // Letting go of the web view is what tells the page its pop-up closed.
        panel.contentView = nil
        if let parent {
            parent.removeChildWindow(panel)
            if parent.isVisible { parent.makeKey() }
        }
        let done = onClose
        onClose = nil
        done?(self)
    }
}

// MARK: - WKUIDelegate

extension PopupWindow: WKUIDelegate {
    /// The page called `window.close()`, as sign-in pop-ups do when finished.
    func webViewDidClose(_ webView: WKWebView) {
        close()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // One pop-up deep: anything it opens in turn opens here.
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = panel.title
        alert.informativeText = message
        alert.beginSheetModal(for: panel) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = panel.title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: panel) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }
}

// MARK: - WKNavigationDelegate

extension PopupWindow: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        guard ["http", "https", "about", "blob", "data", "file", "javascript", ""].contains(scheme) else {
            // Links to other apps, as in the tile: only when clicked.
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
