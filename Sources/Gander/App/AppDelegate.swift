import AppKit
import Combine
import GanderCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private var model: AppModel?
    private var overlay: OverlayController?
    private var hotkeys: HotkeyMonitor?
    private var statusItem: NSStatusItem?
    private var toggleItem: NSMenuItem?
    private var settingsWindow: NSWindow?
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
        self.model = model
        self.overlay = overlay
        self.hotkeys = hotkeys

        overlay.onOpenSettings = { [weak self] in self?.openSettings() }
        hotkeys.onDown = { [weak overlay] in overlay?.shortcutDown() }
        hotkeys.onUp = { [weak overlay] in overlay?.shortcutUp() }
        hotkeys.onCancel = { [weak overlay] in overlay?.shortcutCancelled() }
        hotkeys.start()

        model.$workspace
            .map(\.settings.shortcut)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] shortcut in
                self?.hotkeys?.apply(shortcut)
                self?.toggleItem?.title = "Show Gander (\(shortcut.displayString))"
            }
            .store(in: &cancellables)

        installMainMenu()
        installStatusItem()

        if let output = options.smokeTestOutput {
            SmokeTest.run(model: model, overlay: overlay, hotkeys: hotkeys, output: output)
            return
        }

        if !pendingFiles.isEmpty {
            overlay.addFiles(pendingFiles)
            pendingFiles = []
        } else if options.showOnLaunch || model.isFirstLaunch {
            // On first run there would otherwise be nothing to see but a
            // menu bar icon.
            overlay.showPinned()
        } else {
            overlay.warmUp()
        }

        if let warning = model.loadWarning {
            let alert = NSAlert()
            alert.messageText = "Gander could not read your saved layout"
            alert.informativeText = warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.saveNow()
    }

    /// "Open With → Gander" in Finder, or a file dropped on the app icon.
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
        item.button?.image = .symbol("eye", description: "Gander")

        let menu = NSMenu()
        let shortcut = model?.settings.shortcut.displayString ?? ""
        toggleItem = menu.addItem("Show Gander (\(shortcut))") { [weak self] in self?.overlay?.toggle() }
        menu.addItem("Add Website, File or Widget…") { [weak self] in self?.overlay?.presentLauncher() }
        menu.addItem("Arrange Tiles") { [weak self] in
            self?.overlay?.showPinned()
            self?.overlay?.setEditing(true)
        }
        menu.addItem(.separator())
        menu.addItem("Settings…") { [weak self] in self?.openSettings() }
        menu.addItem(.separator())
        menu.addItem("Quit Gander") { NSApp.terminate(nil) }
        item.menu = menu
        statusItem = item
    }

    /// Never visible (the app has no menu bar of its own), but it is what
    /// makes ⌘C, ⌘V and friends work in the settings window and the overlay.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide Gander", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        // Deliberately no ⌘Q: with the overlay focused it would be far too
        // easy to quit Gander while meaning to quit the app underneath.
        appMenu.addItem(withTitle: "Quit Gander", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
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

    // MARK: - Settings

    private func openSettings() {
        guard let model, let overlay, let hotkeys else { return }
        // The settings window is an ordinary window and would sit behind the
        // overlay.
        overlay.dismiss()

        if settingsWindow == nil {
            let controller = NSHostingController(
                rootView: SettingsView(model: model, hotkeys: hotkeys, overlay: overlay)
            )
            let window = NSWindow(contentViewController: controller)
            window.title = "Gander Settings"
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
