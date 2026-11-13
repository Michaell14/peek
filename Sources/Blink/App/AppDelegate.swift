import AppKit
import Combine
import BlinkCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private var model: AppModel?
    private var overlay: OverlayController?
    private var hotkeys: HotkeyMonitor?
    private var updater: Updater?
    private var statusItem: NSStatusItem?
    private var toggleItem: NSMenuItem?
    private var permissionItem: NSMenuItem?
    private var updateItem: NSMenuItem?
    private var updateTimer: Timer?
    private var settingsWindow: NSWindow?
    private var onboarding: OnboardingController?
    private var cancellables: Set<AnyCancellable> = []
    /// Files handed over by Finder before launch had finished.
    private var pendingFiles: [URL] = []

    init(options: LaunchOptions) {
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isSelfCheck = options.smokeTestOutput != nil
        let model = AppModel(
            directory: options.dataDirectory ?? AppModel.defaultDirectory,
            persists: !isSelfCheck
        )
        let overlay = OverlayController(model: model)
        let hotkeys = HotkeyMonitor(shortcut: model.settings.shortcut)
        let updater = Updater(feed: options.updateFeed)
        self.model = model
        self.overlay = overlay
        self.hotkeys = hotkeys
        self.updater = updater
        let onboarding = OnboardingController(model: model, overlay: overlay, hotkeys: hotkeys)
        self.onboarding = onboarding

        overlay.onOpenSettings = { [weak self] in self?.openSettings() }
        hotkeys.onDown = { [weak overlay] heldFor in overlay?.shortcutDown(heldFor: heldFor) }
        hotkeys.onUp = { [weak overlay] in overlay?.shortcutUp() }
        hotkeys.onCancel = { [weak overlay] in overlay?.shortcutCancelled() }
        hotkeys.start()

        model.$workspace
            .map(\.settings.shortcut)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] shortcut in
                self?.hotkeys?.apply(shortcut)
                self?.toggleItem?.title = "Show Blink (\(shortcut.displayString))"
            }
            .store(in: &cancellables)

        installMainMenu()
        installStatusItem()

        // The menu says so whenever the shortcut is waiting for permission,
        // and whenever there is a newer version.
        hotkeys.$status
            .sink { [weak self] status in
                self?.permissionItem?.isHidden = status != .needsInputMonitoring
            }
            .store(in: &cancellables)
        updater.$state
            .sink { [weak self] state in
                guard let item = self?.updateItem else { return }
                switch state {
                case .available(let offer):
                    item.title = "Update to Blink \(offer.versionText)…"
                    item.isHidden = false
                case .installing:
                    item.title = "Updating Blink…"
                    item.isHidden = false
                case .idle, .checking, .upToDate, .failed:
                    item.isHidden = true
                }
            }
            .store(in: &cancellables)

        if let output = options.smokeTestOutput {
            SmokeTest.run(model: model, overlay: overlay, hotkeys: hotkeys, updater: updater, onboarding: onboarding, output: output)
            return
        }

        // Before anything covers the screen: the default shortcut does
        // nothing until macOS has been told Blink may see it.
        let askedForAccess = explainShortcutPermission()
        scheduleUpdateChecks()

        if !pendingFiles.isEmpty {
            overlay.addFiles(pendingFiles)
            pendingFiles = []
        } else if askedForAccess {
            // The system's own prompt is on its way; stay out from under it.
            overlay.warmUp()
        } else if model.isFirstLaunch, !OnboardingModel.isDone {
            // On first run there would otherwise be nothing to see but a
            // menu bar icon: the tour, which ends on the board.
            onboarding.show()
        } else if options.showOnLaunch || model.isFirstLaunch {
            overlay.showPinned()
        } else {
            overlay.warmUp()
        }

        if let warning = model.loadWarning {
            let alert = NSAlert()
            alert.messageText = "Blink could not read your saved layout"
            alert.informativeText = warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.saveNow()
    }

    /// "Open With → Blink" in Finder, or a file dropped on the app icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let overlay else {
            pendingFiles += urls
            return
        }
        overlay.addFiles(urls)
    }

    /// Opening the app again while it is running shows the overlay.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlay?.showPinned()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Menus

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = BrandGlyph.menuBarImage()

        let menu = NSMenu()
        let shortcut = model?.settings.shortcut.displayString ?? ""
        permissionItem = menu.addItem("Let Blink See the Shortcut…") { [weak self] in
            self?.hotkeys?.requestInputMonitoring()
        }
        permissionItem?.isHidden = true
        updateItem = menu.addItem("Update Blink…") { [weak self] in self?.presentUpdate() }
        updateItem?.isHidden = true
        toggleItem = menu.addItem("Show Blink (\(shortcut))") { [weak self] in self?.overlay?.toggle() }
        menu.addItem("Add Website, File or Widget…") { [weak self] in self?.overlay?.presentLauncher() }
        menu.addItem("Arrange Tiles") { [weak self] in
            self?.overlay?.showPinned()
            self?.overlay?.setEditing(true)
        }
        menu.addItem(.separator())
        menu.addItem("Blink Tour…") { [weak self] in self?.onboarding?.show() }
        menu.addItem("Settings…") { [weak self] in self?.openSettings() }
        menu.addItem("Check for Updates…") { [weak self] in self?.checkForUpdates() }
        menu.addItem(.separator())
        menu.addItem("Quit Blink") { NSApp.terminate(nil) }
        item.menu = menu
        statusItem = item
    }

    /// Never visible (the app has no menu bar of its own), but it is what
    /// makes ⌘C, ⌘V and friends work in the settings window and the overlay.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide Blink", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        // Deliberately no ⌘Q: with the overlay focused it would be far too
        // easy to quit Blink while meaning to quit the app underneath.
        appMenu.addItem(withTitle: "Quit Blink", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    // MARK: - The shortcut's permission

    /// Says why Blink is about to ask for Input Monitoring. Returns true if
    /// the system prompt follows.
    private func explainShortcutPermission() -> Bool {
        guard let hotkeys, hotkeys.status == .needsInputMonitoring else { return false }
        let wanted = hotkeys.shortcut.displayString

        let alert = NSAlert()
        alert.messageText = "Let Blink see \(wanted)"
        alert.informativeText = "Blink appears while you hold \(wanted). macOS only shows that key to apps "
            + "you have allowed under Input Monitoring.\n\n"
            + "Blink looks for the shortcut and nothing else. It does not record what you type. "
            + "If you would rather not allow it, choose a different shortcut in Blink's Settings: "
            + "an ordinary key combination needs no permission."
        alert.addButton(withTitle: "Allow…")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        hotkeys.requestInputMonitoring()
        return true
    }

    // MARK: - Updates

    /// Asks once a day, quietly. A newer version is announced once; after
    /// that it waits in the menu.
    private func scheduleUpdateChecks() {
        guard let updater, updater.current != nil else { return }
        // Not in the first seconds, when a login is busy enough already.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            onMainActor { self?.checkForUpdatesIfDue() }
        }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            onMainActor { self?.checkForUpdatesIfDue() }
        }
    }

    private func checkForUpdatesIfDue() {
        guard let updater, model?.settings.checksForUpdates == true, updater.isDue else { return }
        Task { @MainActor in
            if case .available(let offer) = await updater.check(), updater.shouldAnnounce(offer) {
                self.presentUpdate()
            }
        }
    }

    /// "Check for Updates…": always answers, whatever it finds.
    private func checkForUpdates() {
        guard let updater else { return }
        overlay?.dismiss()
        Task { @MainActor in
            switch await updater.check() {
            case .available:
                self.presentUpdate()
            case .upToDate:
                self.inform("Blink is up to date", "You have \(updater.currentText), the newest version.")
            case .failed(let reason):
                self.inform("Blink could not check for updates", reason)
            case .idle, .checking, .installing:
                break
            }
        }
    }

    private func presentUpdate() {
        guard let updater, case .available(let offer) = updater.state else { return }
        overlay?.dismiss()
        let installs = offer.archive != nil

        let alert = NSAlert()
        alert.messageText = "Blink \(offer.versionText) is available"
        alert.informativeText = installs
            ? "You have \(updater.currentText). Blink will download the new version, check it, and start again."
            : "You have \(updater.currentText). This version has to be downloaded and put in place by hand."
        alert.addButton(withTitle: installs ? "Install and Relaunch" : "Download")
        alert.addButton(withTitle: "Later")
        if offer.page != nil { alert.addButton(withTitle: "What’s New") }
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if installs {
                install(offer)
            } else {
                openDownloadPage()
            }
        case .alertThirdButtonReturn:
            if let page = offer.page { NSWorkspace.shared.open(page) }
        default:
            break
        }
    }

    private func install(_ offer: UpdateOffer) {
        guard let updater else { return }
        model?.saveNow()
        Task { @MainActor in
            do {
                try await updater.install(offer)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Blink could not update itself"
                alert.informativeText = error.localizedDescription
                    + "\n\nYou can download the new version and replace this one by hand."
                alert.addButton(withTitle: "Download")
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn { self.openDownloadPage() }
            }
        }
    }

    private func openDownloadPage() {
        if let page = updater?.source.downloadPage { NSWorkspace.shared.open(page) }
    }

    private func inform(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Settings

    private func openSettings() {
        guard let model, let overlay, let hotkeys else { return }
        // The settings window is an ordinary window and would sit behind the
        // overlay.
        overlay.dismiss()

        if settingsWindow == nil {
            let controller = NSHostingController(
                rootView: SettingsView(
                    model: model, hotkeys: hotkeys, overlay: overlay,
                    checkForUpdates: { [weak self] in self?.checkForUpdates() }
                )
            )
            let window = NSWindow(contentViewController: controller)
            window.title = "Blink Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            // Size it before centring: until its first layout the window is
            // tiny, and centring that leaves the real one off to one side.
            window.setContentSize(SettingsView.size)
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
