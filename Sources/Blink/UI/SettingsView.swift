import AppKit
import BlinkCore
import SwiftUI

extension AppModel {
    /// A two-way binding to one setting.
    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { value in self.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var hotkeys: HotkeyMonitor
    let overlay: OverlayController
    var checkForUpdates: () -> Void = {}

    var body: some View {
        TabView {
            GeneralSettingsView(model: model, hotkeys: hotkeys)
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsView(model: model)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            WebSettingsView(model: model, overlay: overlay)
                .tabItem { Label("Web", systemImage: "globe") }
            AboutSettingsView(model: model, checkForUpdates: checkForUpdates)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    static let size = CGSize(width: 540, height: 500)
}

/// Explanatory text under a group of settings.
private struct Footnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - General

@MainActor
private struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var hotkeys: HotkeyMonitor

    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    private struct DisplayChoice: Identifiable {
        let id: String
        let name: String
    }

    private var displays: [DisplayChoice] {
        NSScreen.screens.map { DisplayChoice(id: $0.displayKey, name: $0.localizedName) }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Shortcut") {
                    ShortcutRecorderField(shortcut: model.binding(\.shortcut)) { isRecording in
                        if isRecording {
                            hotkeys.pause()
                        } else {
                            hotkeys.resume()
                        }
                    }
                    .frame(width: 190, height: 26)
                }
                shortcutStatus
                globeKeyNote
                LabeledContent("Tap speed") {
                    Slider(value: model.binding(\.tapThreshold), in: 0.15...0.6) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Quick").font(.caption)
                    } maximumValueLabel: {
                        Text("Relaxed").font(.caption)
                    }
                    .frame(width: 240)
                }
            } footer: {
                Footnote("Hold the shortcut to peek and let go to return. Tap it to keep Blink open. "
                    + "Click the field and press modifier keys on their own (for example Right ⌘ or fn) "
                    + "to use them as the shortcut.")
            }

            Section {
                Picker("Open on", selection: model.binding(\.displayTarget.kind)) {
                    Text("The display with the pointer").tag(DisplayTarget.Kind.pointer)
                    Text("The display with the active window").tag(DisplayTarget.Kind.active)
                    Text("A specific display").tag(DisplayTarget.Kind.fixed)
                }
                if model.settings.displayTarget.kind == .fixed {
                    Picker("Display", selection: Binding(
                        get: { model.settings.displayTarget.displayKey ?? displays.first?.id ?? "" },
                        set: { key in model.updateSettings { $0.displayTarget.displayKey = key } }
                    )) {
                        ForEach(displays) { display in
                            Text(display.name).tag(display.id)
                        }
                    }
                }
                Toggle("Use the same layout on every display", isOn: model.binding(\.syncAcrossDisplays))
            }

            Section {
                Toggle("Open Blink at login", isOn: Binding(
                    get: { opensAtLogin },
                    set: { enabled in
                        loginItemError = LoginItem.setEnabled(enabled)
                        opensAtLogin = LoginItem.isEnabled
                    }
                ))
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var shortcutStatus: some View {
        switch hotkeys.status {
        case .needsInputMonitoring:
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "macOS only shows this shortcut to apps allowed under Input Monitoring. "
                        + "Blink looks for the shortcut and nothing else; it does not record what you type.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                Button("Allow Input Monitoring…") { hotkeys.requestInputMonitoring() }
            }
        case .unavailable:
            Label("Another app or the system already uses this shortcut.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        case .active, .inactive:
            EmptyView()
        }
    }

    /// macOS has its own plans for a press of fn: the emoji picker, the next
    /// input source, or dictation. Blink cannot stop that, only say where to.
    @ViewBuilder
    private var globeKeyNote: some View {
        if model.settings.shortcut.isFunctionKeyAlone, GlobeKey.hasSystemAction {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "macOS also does something of its own when fn is pressed. To have it open Blink and "
                        + "nothing else, set “Press 🌐 key to” to “Do Nothing” in Keyboard settings.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Button("Open Keyboard Settings…") { SystemSettings.openKeyboard() }
            }
        }
    }
}

/// What macOS does when fn (the globe key) is pressed by itself.
enum GlobeKey {
    /// False only when the user has chosen "Do Nothing".
    static var hasSystemAction: Bool {
        let setting = UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int
        return setting != 0
    }
}

// MARK: - Appearance

private struct AppearanceSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Backdrop") {
                LabeledContent("Dimming") {
                    Slider(value: model.binding(\.backdropOpacity), in: 0...0.95)
                        .frame(width: 240)
                }
                Toggle("Blur what is behind", isOn: model.binding(\.backdropBlur))
                LabeledContent("Fade") {
                    Slider(value: model.binding(\.fadeDuration), in: 0...0.4)
                        .frame(width: 240)
                }
            }
            Section("Tiles") {
                LabeledContent("Corner radius") {
                    Slider(value: model.binding(\.tileCornerRadius), in: 0...28)
                        .frame(width: 240)
                }
                LabeledContent("Gap between tiles") {
                    Slider(value: model.binding(\.tileGap), in: 0...40)
                        .frame(width: 240)
                }
                LabeledContent("Margin around the edge") {
                    Slider(value: model.binding(\.canvasPadding), in: 0...120)
                        .frame(width: 240)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Web

@MainActor
private struct WebSettingsView: View {
    @ObservedObject var model: AppModel
    let overlay: OverlayController

    @State private var filters = ""
    @State private var filterStatus = ""
    @State private var clearedMessage: String?

    private static let searchEngines: [(name: String, template: String)] = [
        ("DuckDuckGo", "https://duckduckgo.com/?q=%s"),
        ("Google", "https://www.google.com/search?q=%s"),
        ("Bing", "https://www.bing.com/search?q=%s"),
        ("Brave", "https://search.brave.com/search?q=%s"),
        ("Kagi", "https://kagi.com/search?q=%s"),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Block ads", isOn: model.binding(\.blockAds))
                Toggle("Block trackers", isOn: model.binding(\.blockTrackers))
                Toggle("Hide cookie banners", isOn: model.binding(\.hideCookieBanners))
            } footer: {
                Footnote("Blocking only applies to requests a page makes to other sites, "
                    + "so dashboards you open directly keep working.")
            }

            Section {
                Picker("Pages appear", selection: model.binding(\.webColorScheme)) {
                    Text("Like the system").tag(ColorSchemePreference.system)
                    Text("Light").tag(ColorSchemePreference.light)
                    Text("Dark").tag(ColorSchemePreference.dark)
                }
                Picker("Search with", selection: model.binding(\.searchTemplate)) {
                    ForEach(Self.searchEngines, id: \.template) { engine in
                        Text(engine.name).tag(engine.template)
                    }
                }
            }

            Section {
                TextEditor(text: $filters)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 70)
                HStack {
                    Text(filterStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply") { applyFilters() }
                        .disabled(filters == model.settings.customFilters)
                }
            } header: {
                Text("Your own filters")
            } footer: {
                Footnote("One rule per line in Adblock Plus syntax, for example ||ads.example.com^ or example.com##.banner")
            }

            Section("Browsing data") {
                HStack {
                    Button("Clear Cache") { clear(.cache, message: "Cache cleared.") }
                    Button("Clear Cookies and Site Data") {
                        clear(.cookiesAndSiteData, message: "Cookies and site data cleared. You are signed out of websites.")
                    }
                    Spacer()
                }
                if let clearedMessage {
                    Text(clearedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            filters = model.settings.customFilters
            describeFilters()
        }
    }

    private func applyFilters() {
        model.updateSettings { $0.customFilters = filters }
        describeFilters()
        // Compiling takes a moment; report a failure once it is known.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            onMainActor {
                if let error = overlay.customFilterError {
                    filterStatus = "Could not be used: \(error)"
                }
            }
        }
    }

    private func describeFilters() {
        let result = FilterListParser.parse(filters)
        if result.rules.isEmpty, result.skipped == 0 {
            filterStatus = ""
        } else if result.skipped == 0 {
            filterStatus = "\(result.rules.count) rules"
        } else {
            filterStatus = "\(result.rules.count) rules, \(result.skipped) lines not supported"
        }
    }

    private func clear(_ data: WebEnvironment.BrowsingData, message: String) {
        clearedMessage = nil
        overlay.clearBrowsingData(data) {
            clearedMessage = message
        }
    }
}

// MARK: - About

@MainActor
private struct AboutSettingsView: View {
    @ObservedObject var model: AppModel
    let checkForUpdates: () -> Void

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            Text("Blink")
                .font(.system(size: 22, weight: .semibold))
            Text("Version \(version)")
                .foregroundStyle(.secondary)
            Text("Hold a key to glance at the things you check all day,\nthen let go and carry on.")
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            Text("Free and open source under the MIT license. Your layouts and browsing data stay on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            HStack(spacing: 14) {
                Toggle("Check for updates every day", isOn: model.binding(\.checksForUpdates))
                    .toggleStyle(.checkbox)
                Button("Check Now…", action: checkForUpdates)
            }
            .padding(.top, 8)
            Text("The check asks GitHub for the newest version. It sends nothing about you or this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Show Data Folder in Finder") {
                try? FileManager.default.createDirectory(at: model.directory, withIntermediateDirectories: true)
                NSWorkspace.shared.activateFileViewerSelecting([model.directory])
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
