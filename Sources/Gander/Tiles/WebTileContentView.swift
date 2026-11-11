import AppKit
import GanderCore
import WebKit

/// WKWebView with a few extra entries in its right-click menu.
final class TileWebView: WKWebView {
    var extraMenuItems: (() -> [NSMenuItem])?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let items = extraMenuItems?(), !items.isEmpty else { return }
        menu.addItem(.separator())
        for item in items {
            menu.addItem(item)
        }
    }
}

/// WKUserContentController keeps its handlers alive, so hand it something
/// that does not in turn keep the tile alive.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

final class WebTileContentView: TileContentView {
    private let webView: TileWebView
    private var web: WebContent
    private var lastLoad = Date()
    private var hasLoaded = false
    private var refreshTimer: Timer?
    private var observations: [NSKeyValueObservation] = []
    private let progressBar = NSView()
    private var errorView: NSView?
    private var isOverlayVisible = false
    private var isInteractive = false

    /// True while the page is in "click an element to hide it" mode.
    private(set) var isPicking = false {
        didSet {
            if isPicking != oldValue { context.pickerDidChange() }
        }
    }

    /// Our scripts run apart from the page's own, so a page can neither see
    /// nor call the handler that saves hidden elements.
    private let scriptWorld = WKContentWorld.defaultClient

    init(tile: Tile, web: WebContent, settings: AppSettings, context: TileContext) {
        self.web = web
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = WebEnvironment.desktopUserAgentSuffix
        // Tiles stay loaded while the overlay is hidden; nothing should start
        // making noise from behind the scenes.
        configuration.mediaTypesRequiringUserActionForPlayback = [.audio]
        webView = TileWebView(frame: .zero, configuration: configuration)
        super.init(tile: tile, settings: settings, context: context)

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true
        webView.extraMenuItems = { [weak self] in self?.contextMenuItems() ?? [] }
        addSubview(webView)
        webView.pinToSuperviewEdges()

        progressBar.wantsLayer = true
        progressBar.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        progressBar.isHidden = true
        addSubview(progressBar)

        webView.configuration.userContentController.add(
            WeakMessageHandler(self), contentWorld: scriptWorld, name: ElementHiding.messageHandlerName
        )
        installUserScripts()
        applyUserAgent()
        applyAppearance()
        webView.pageZoom = web.zoom
        observeWebView()
        scheduleRefresh()

        // Wait for the blocking rules so the first load is already filtered.
        if context.web.isReady {
            applyRuleLists()
            loadStartPage()
        }
    }

    override var title: String {
        if let title = webView.title, !title.isEmpty { return title }
        return URLInput.displayHost(for: webView.url ?? web.url)
    }

    var currentURL: URL { webView.url ?? web.url }
    var canGoBack: Bool { webView.canGoBack }
    var canGoForward: Bool { webView.canGoForward }

    // MARK: - TileContentView

    override func apply(tile: Tile, settings: AppSettings) {
        let oldSettings = self.settings
        super.apply(tile: tile, settings: settings)
        guard case .web(let updated) = tile.content else { return }
        let old = web
        web = updated

        if updated.hiddenElements != old.hiddenElements || settings.hideCookieBanners != oldSettings.hideCookieBanners {
            installUserScripts()
            run(ElementHiding.userScript(for: updated.hiddenElements))
        }
        if updated.zoom != old.zoom {
            webView.pageZoom = updated.zoom
        }
        if updated.refreshInterval != old.refreshInterval {
            scheduleRefresh()
        }
        if settings.webColorScheme != oldSettings.webColorScheme {
            applyAppearance()
        }
        if updated.prefersMobileSite != old.prefersMobileSite {
            applyUserAgent()
            reload()
        }
        if updated.url != old.url {
            loadStartPage()
        }
    }

    override func overlayWillShow() {
        isOverlayVisible = true
        applyAppearance()
    }

    override func overlayDidHide() {
        isOverlayVisible = false
        stopPicker()
    }

    override func interactivityDidChange(_ isInteractive: Bool) {
        self.isInteractive = isInteractive
        if !isInteractive { stopPicker() }
    }

    override func openExternally() {
        NSWorkspace.shared.open(currentURL)
        dismissOverlay()
    }

    override func tearDown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        observations.removeAll()
        stopPicker()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: ElementHiding.messageHandlerName, contentWorld: scriptWorld
        )
    }

    override func layout() {
        super.layout()
        layoutProgressBar()
        errorView?.frame = bounds
    }

    /// The shared blocking rules were (re)compiled.
    func ruleListsDidChange() {
        applyRuleLists()
        if !hasLoaded { loadStartPage() }
    }

    // MARK: - Navigation

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func reload() {
        hideError()
        lastLoad = Date()
        if webView.url == nil {
            loadStartPage()
        } else {
            webView.reload()
        }
    }

    func loadStartPage() {
        hideError()
        hasLoaded = true
        lastLoad = Date()
        if web.url.isFileURL {
            webView.loadFileURL(web.url, allowingReadAccessTo: web.url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: web.url))
        }
    }

    // MARK: - Hiding elements

    func startPicker() {
        guard !isPicking else { return }
        isPicking = true
        run(ElementHiding.pickerScript)
        window?.makeFirstResponder(webView)
    }

    func stopPicker() {
        guard isPicking else { return }
        isPicking = false
        run(ElementHiding.stopPickerScript)
    }

    private func run(_ script: String) {
        webView.evaluateJavaScript(script, in: nil, in: scriptWorld, completionHandler: nil)
    }

    private func installUserScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(
            source: ElementHiding.userScript(for: web.hiddenElements),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: scriptWorld
        ))
        if settings.hideCookieBanners {
            controller.addUserScript(WKUserScript(
                source: ElementHiding.scrollUnlockScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: scriptWorld
            ))
        }
    }

    private var hiddenElementsOnThisSite: [HiddenElement] {
        guard let host = currentURL.host else { return [] }
        let site = ElementHiding.normalizedHost(host)
        return web.hiddenElements.filter { site == $0.host || site.hasSuffix("." + $0.host) }
    }

    // MARK: - Configuration

    private func applyRuleLists() {
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        for list in context.web.ruleLists {
            controller.add(list)
        }
    }

    private func applyUserAgent() {
        // nil falls back to the desktop agent built from the configuration.
        webView.customUserAgent = web.prefersMobileSite ? WebEnvironment.mobileUserAgent : nil
    }

    /// Pages follow the system's light/dark setting (or the user's override)
    /// rather than the always-dark overlay around them.
    private func applyAppearance() {
        switch settings.webColorScheme {
        case .system: webView.appearance = NSApp.effectiveAppearance
        case .light: webView.appearance = NSAppearance(named: .aqua)
        case .dark: webView.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func observeWebView() {
        observations = [
            webView.observe(\.estimatedProgress) { [weak self] _, _ in
                onMainActor { self?.layoutProgressBar() }
            },
            webView.observe(\.isLoading) { [weak self] _, _ in
                onMainActor { self?.layoutProgressBar() }
            },
            webView.observe(\.title) { [weak self] _, _ in
                onMainActor { self?.titleDidChange?() }
            },
        ]
    }

    private func layoutProgressBar() {
        let progress = webView.estimatedProgress
        progressBar.isHidden = !webView.isLoading || progress >= 1
        progressBar.frame = CGRect(x: 0, y: 0, width: bounds.width * progress, height: 2)
    }

    // MARK: - Auto-refresh

    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard web.refreshInterval > 0 else { return }
        let period = min(max(web.refreshInterval / 4, 1), 15)
        let timer = Timer.scheduledTimer(withTimeInterval: period, repeats: true) { [weak self] _ in
            onMainActor { self?.refreshIfDue() }
        }
        timer.tolerance = period / 4
        refreshTimer = timer
    }

    private func refreshIfDue() {
        let isInUse = isInteractive || isPicking || webView.isLoading
        if RefreshPolicy.isDue(lastLoaded: lastLoad, interval: web.refreshInterval, now: Date(), isInUse: isInUse) {
            reload()
        }
    }

    // MARK: - Errors

    private func showError(_ message: String) {
        hideError()
        let view = MessageView(
            symbol: "wifi.exclamationmark",
            text: "\(URLInput.displayHost(for: currentURL))\n\(message)",
            buttonTitle: "Try Again"
        ) { [weak self] in
            self?.reload()
        }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(white: 0.11, alpha: 1).cgColor
        view.frame = bounds
        addSubview(view)
        errorView = view
    }

    private func hideError() {
        errorView?.removeFromSuperview()
        errorView = nil
    }

    // MARK: - Menus

    private func contextMenuItems() -> [NSMenuItem] {
        [
            ClosureMenuItem(title: "Open Page in Browser") { [weak self] in self?.openExternally() },
            ClosureMenuItem(title: "Hide Elements…") { [weak self] in self?.startPicker() },
        ]
    }

    override func addMenuItems(to menu: NSMenu) {
        menu.addItem("Back", enabled: canGoBack) { [weak self] in self?.goBack() }
        menu.addItem("Forward", enabled: canGoForward) { [weak self] in self?.goForward() }
        menu.addItem("Reload") { [weak self] in self?.reload() }
        menu.addItem("Go to Start Page") { [weak self] in self?.loadStartPage() }
        menu.addItem(.separator())

        menu.addItem("Open in Browser") { [weak self] in self?.openExternally() }
        menu.addItem("Copy Link") { [weak self] in
            guard let self else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(self.currentURL.absoluteString, forType: .string)
        }
        menu.addItem(.separator())

        menu.addItem("Change Address…") { [weak self] in self?.promptForAddress() }
        menu.addItem("Use This Page as Start Page", enabled: webView.url != nil && webView.url != web.url) { [weak self] in
            guard let self, let url = self.webView.url else { return }
            self.updateWeb { $0.url = url }
        }
        menu.addItem(.separator())

        menu.addItem("Hide Elements…") { [weak self] in self?.startPicker() }
        let hidden = hiddenElementsOnThisSite
        menu.addItem("Show Hidden Elements (\(hidden.count))", enabled: !hidden.isEmpty) { [weak self] in
            self?.updateWeb { web in
                web.hiddenElements.removeAll { hidden.contains($0) }
            }
            self?.reload()
        }
        menu.addItem(.separator())

        menu.addSubmenu("Auto-Refresh") { submenu in
            for interval in RefreshPolicy.presets {
                submenu.addItem(RefreshPolicy.label(for: interval), checked: web.refreshInterval == interval) { [weak self] in
                    self?.updateWeb { $0.refreshInterval = interval }
                }
            }
        }
        menu.addSubmenu("Zoom") { submenu in
            for zoom in [0.5, 0.67, 0.75, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5] {
                submenu.addItem("\(Int((zoom * 100).rounded()))%", checked: abs(web.zoom - zoom) < 0.001) { [weak self] in
                    self?.updateWeb { $0.zoom = zoom }
                }
            }
        }
        menu.addItem("Request Mobile Site", checked: web.prefersMobileSite) { [weak self] in
            self?.updateWeb { $0.prefersMobileSite.toggle() }
        }
    }

    private func updateWeb(_ change: (inout WebContent) -> Void) {
        updateTile { tile in
            guard case .web(var web) = tile.content else { return }
            change(&web)
            tile.content = .web(web)
        }
    }

    private func promptForAddress() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Change Address"
        alert.informativeText = "The page this tile opens to."
        let field = NSTextField(string: web.url.absoluteString)
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let searchTemplate = settings.searchTemplate
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn,
                  let url = URLInput.resolve(field.stringValue, searchTemplate: searchTemplate) else { return }
            self?.updateWeb { $0.url = url }
        }
    }

    /// Sends keyboard input to the page.
    func focusPage() {
        window?.makeFirstResponder(webView)
    }

    /// Runs a script next to Gander's own and returns its result as text.
    /// Used by the self-check to look inside the page.
    func evaluate(_ script: String) async -> String {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script, in: nil, in: scriptWorld) { result in
                switch result {
                case .success(let value): continuation.resume(returning: String(describing: value))
                case .failure(let error): continuation.resume(returning: "error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Page dialogs are only worth showing to someone who is looking.
    private var dialogWindow: NSWindow? {
        isOverlayVisible && isInteractive ? window : nil
    }
}

// MARK: - WKScriptMessageHandler

extension WebTileContentView: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard isPicking,
              message.name == ElementHiding.messageHandlerName,
              message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "hide":
            let host = ElementHiding.normalizedHost(message.frameInfo.securityOrigin.host)
            guard let selector = body["selector"] as? String,
                  ElementHiding.isValidSelector(selector), !host.isEmpty else { return }
            let element = HiddenElement(host: host, selector: selector)
            updateWeb { web in
                if !web.hiddenElements.contains(element) {
                    web.hiddenElements.append(element)
                }
            }
        case "done":
            stopPicker()
        default:
            break
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebTileContentView: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        let isUserClick = navigationAction.navigationType == .linkActivated

        // mailto:, tel:, app links and the like belong to other apps, but only
        // when someone actually clicked them.
        guard ["http", "https", "about", "blob", "data", "file", "javascript"].contains(scheme) else {
            if isUserClick { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
            return
        }
        if isUserClick, navigationAction.modifierFlags.contains(.command), scheme.hasPrefix("http") {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        hideError()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // The picker lived in the page that just went away.
        isPicking = false
        lastLoad = Date()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        titleDidChange?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        reload()
    }

    private func report(_ error: Error) {
        let error = error as NSError
        // Cancelled loads and loads that turned into downloads are not failures.
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled { return }
        if error.domain == "WebKitErrorDomain", error.code == 102 { return }
        showError(error.localizedDescription)
    }
}

// MARK: - WKDownloadDelegate

extension WebTileContentView: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let manager = FileManager.default
        let folder = manager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory
        let name = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension

        var candidate = folder.appendingPathComponent(name)
        var counter = 2
        while manager.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            counter += 1
        }
        completionHandler(candidate)
    }
}

// MARK: - WKUIDelegate

extension WebTileContentView: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // A tile is a single page: links that ask for a new window open here.
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
        guard let dialogWindow else {
            completionHandler()
            return
        }
        let alert = NSAlert()
        alert.messageText = URLInput.displayHost(for: currentURL)
        alert.informativeText = message
        alert.beginSheetModal(for: dialogWindow) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let dialogWindow else {
            completionHandler(false)
            return
        }
        let alert = NSAlert()
        alert.messageText = URLInput.displayHost(for: currentURL)
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: dialogWindow) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        guard let dialogWindow else {
            completionHandler(nil)
            return
        }
        let alert = NSAlert()
        alert.messageText = URLInput.displayHost(for: currentURL)
        alert.informativeText = prompt
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: dialogWindow) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        guard let dialogWindow else {
            completionHandler(nil)
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.beginSheetModal(for: dialogWindow) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }
}
