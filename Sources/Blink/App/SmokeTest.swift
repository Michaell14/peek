import AppKit
import BlinkCore
import SwiftUI

/// An end-to-end self-check: drives the real overlay through its main states
/// and writes what it saw to `smoke.json`, with screenshots alongside.
///
///     Blink --smoke-test <output directory>
///
/// If `BLINK_SMOKE_URL` points at `Tests/Fixtures/page.html` served over
/// HTTP, it also checks content blocking and element hiding inside a real
/// page. It uses an in-memory workspace, so it never touches a real layout.
@MainActor
enum SmokeTest {
    private static let pageTitle = "Blink self-check page"

    private static var desktopStandIn: NSWindow?

    /// The machines this runs on have a plain black desktop, which hides what
    /// the overlay's blur and glass look like. Put something colourful behind
    /// it: a gradient with a couple of pale rectangles for open windows.
    private static func showDesktopStandIn() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true

        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.frame = view.bounds
        gradient.colors = [
            NSColor(srgbRed: 0.09, green: 0.16, blue: 0.44, alpha: 1).cgColor,
            NSColor(srgbRed: 0.52, green: 0.22, blue: 0.58, alpha: 1).cgColor,
            NSColor(srgbRed: 0.98, green: 0.56, blue: 0.32, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        view.layer?.addSublayer(gradient)

        let size = view.bounds.size
        for (index, unit) in [CGRect(x: 0.07, y: 0.12, width: 0.5, height: 0.64), CGRect(x: 0.45, y: 0.26, width: 0.47, height: 0.6)].enumerated() {
            let pane = CALayer()
            pane.frame = CGRect(
                x: unit.minX * size.width, y: unit.minY * size.height,
                width: unit.width * size.width, height: unit.height * size.height
            )
            pane.backgroundColor = NSColor(white: index == 0 ? 0.97 : 0.14, alpha: 1).cgColor
            pane.cornerRadius = 11
            pane.shadowOpacity = 0.35
            pane.shadowRadius = 24
            view.layer?.addSublayer(pane)
        }
        window.contentView = view
        window.orderFrontRegardless()
        desktopStandIn = window
    }

    /// A few conversations, as the Messages widget would read them.
    private static func sampleMessages() -> MessagesService.SampleData {
        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let conversations = [
            Conversation(id: 1, guid: "iMessage;-;maya@example.com", title: "Maya Chen", handles: ["maya@example.com"],
                         isGroup: false, lastText: "Can we move the review to 3?", lastDate: ago(2), lastFromMe: false, unread: 1),
            Conversation(id: 2, guid: "iMessage;+;chat1", title: "Design team", handles: ["leo@example.com", "ana@example.com"],
                         isGroup: true, lastText: "Leo: The new build is up", lastDate: ago(18), lastFromMe: false, unread: 2),
            Conversation(id: 3, guid: "iMessage;-;+15550102233", title: "Sam Okafor", handles: ["+15550102233"],
                         isGroup: false, lastText: "Sounds good, see you then", lastDate: ago(70), lastFromMe: true, unread: 0),
            Conversation(id: 4, guid: "SMS;-;+15550109999", title: "+1 555 010 9999", handles: ["+15550109999"],
                         isGroup: false, lastText: "Your table is ready", lastDate: ago(60 * 30), lastFromMe: false, unread: 0),
        ]
        let thread = [
            ChatMessage(id: 11, text: "Morning! Did you see the numbers?", date: ago(40), fromMe: false, sender: "Maya Chen"),
            ChatMessage(id: 12, text: "Yes, sign-ups are up again", date: ago(35), fromMe: true, sender: nil),
            ChatMessage(id: 13, text: "Can we move the review to 3?", date: ago(2), fromMe: false, sender: "Maya Chen"),
        ]
        return MessagesService.SampleData(conversations: conversations, threads: [1: thread])
    }

    /// A plausible day: overlapping meetings, an all-day event, something
    /// tomorrow, and reminders in every state.
    private static func sampleData() -> EventKitService.SampleData {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func time(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: day, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        func event(_ title: String, _ start: Date, _ end: Date, _ color: NSColor, allDay: Bool = false, location: String? = nil) -> EventItem {
            EventItem(
                id: title, title: title, start: start, end: end, isAllDay: allDay,
                color: Color(nsColor: color), location: location
            )
        }
        func reminder(_ title: String, _ due: Date?, hasTime: Bool = false, list: String = "Reminders", _ color: NSColor = .systemOrange) -> ReminderItem {
            ReminderItem(id: title, title: title, due: due, hasTime: hasTime, listName: list, color: Color(nsColor: color))
        }
        let hour = calendar.component(.hour, from: Date())
        // Keep the busy part of the day near "now", where the day view opens.
        let anchor = min(max(hour, 1), 19)
        return EventKitService.SampleData(
            events: [
                event("Release day", today, time(1, 0), .systemGreen, allDay: true),
                event("Design review", time(0, anchor, 0), time(0, anchor + 1, 0), .systemBlue, location: "Room 4"),
                event("1:1 with Sam", time(0, anchor, 30), time(0, anchor + 1, 30), .systemPurple),
                event("Standup", time(0, anchor, 30), time(0, anchor, 45), .systemOrange),
                event("Lunch", time(0, anchor + 2, 0), time(0, anchor + 2, 45), .systemTeal),
                event("Planning", time(1, 11, 0), time(1, 12, 0), .systemBlue),
                event("Dentist", time(3, 15, 30), time(3, 16, 0), .systemRed, location: "12 High Street"),
            ],
            reminders: [
                reminder("Send the invoice", time(-1, 0)),
                reminder("Water the plants", today),
                reminder("Call the dentist", time(0, 23, 30), hasTime: true),
                reminder("Renew passport", time(6, 0), list: "Admin", .systemBlue),
                reminder("Read that book", nil, list: "Someday", .systemPurple),
            ]
        )
    }

    static func run(model: AppModel, overlay: OverlayController, hotkeys: HotkeyMonitor, updater: Updater, output: URL) {
        let pageURL = ProcessInfo.processInfo.environment["BLINK_SMOKE_URL"].flatMap(URL.init(string:))

        model.update { workspace in
            // A generous tap window keeps a busy machine from turning the
            // tap below into a hold.
            workspace.settings.tapThreshold = 0.6
            guard let pageURL else { return }
            workspace.settings.customFilters = "||localhost^\n##.custom-hidden"
            workspace.updateBoard(workspace.sharedBoardID) { board in
                board.tiles = [
                    Tile(content: .widget(.clock(ClockConfig(zones: [ClockConfig.localZone, "Asia/Tokyo"])))),
                    Tile(content: .widget(.notes(NotesConfig(text: "Self-check")))),
                    Tile(content: .web(WebContent(url: pageURL))),
                ]
            }
        }

        Task { @MainActor in
            var failures: [String] = []
            var snapshots: [String: Any] = [:]
            var performance: [String: Any] = [:]

            @MainActor func pause(_ seconds: Double) async {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }

            @MainActor func expect(_ step: String, _ checks: [(String, Bool)]) {
                snapshots[step] = overlay.snapshot()
                for (name, passed) in checks where !passed {
                    failures.append("\(step): \(name)")
                }
            }

            @MainActor func flag(_ key: String) -> Bool {
                overlay.snapshot()[key] as? Bool ?? false
            }

            @MainActor func tileFrames() -> [CGRect] {
                let tiles = overlay.snapshot()["tiles"] as? [[String: Any]] ?? []
                return tiles.compactMap { tile in
                    guard let frame = tile["frame"] as? [Double], frame.count == 4 else { return nil }
                    return CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3])
                }
            }

            /// Tile frames by id, in the board's coordinates (origin top-left).
            @MainActor func framesByID() -> [String: CGRect] {
                let tiles = overlay.snapshot()["tiles"] as? [[String: Any]] ?? []
                var result: [String: CGRect] = [:]
                for tile in tiles {
                    guard let id = tile["id"] as? String, let frame = tile["frame"] as? [Double], frame.count == 4 else { continue }
                    result[id] = CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3])
                }
                return result
            }

            @MainActor func tileIDs() -> [String] {
                let tiles = overlay.snapshot()["tiles"] as? [[String: Any]] ?? []
                return tiles.compactMap { $0["id"] as? String }
            }

            @MainActor func tileKinds() -> [String] {
                let tiles = overlay.snapshot()["tiles"] as? [[String: Any]] ?? []
                return tiles.compactMap { $0["kind"] as? String }
            }

            // Input is simulated by placing events on the app's own queue, so
            // it travels the same path a real click or key press would.
            @MainActor func mouse(_ type: NSEvent.EventType, at point: CGPoint) {
                let snapshot = overlay.snapshot()
                let height = (snapshot["panelFrame"] as? [Double])?[3] ?? 0
                guard let event = NSEvent.mouseEvent(
                    with: type,
                    // Window coordinates start at the bottom-left.
                    location: CGPoint(x: point.x, y: height - point.y),
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: snapshot["windowNumber"] as? Int ?? 0,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: type == .leftMouseUp ? 0 : 1
                ) else { return }
                NSApp.postEvent(event, atStart: false)
            }

            @MainActor func drag(from start: CGPoint, to end: CGPoint) async {
                mouse(.leftMouseDown, at: start)
                await pause(0.15)
                for step in 1...8 {
                    let t = CGFloat(step) / 8
                    mouse(.leftMouseDragged, at: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
                    await pause(0.04)
                }
                mouse(.leftMouseUp, at: end)
                await pause(0.6)
            }

            @MainActor func click(at point: CGPoint) async {
                mouse(.leftMouseDown, at: point)
                mouse(.leftMouseUp, at: point)
                await pause(0.6)
            }

            @MainActor func press(_ characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags = []) async {
                let windowNumber = overlay.snapshot()["windowNumber"] as? Int ?? 0
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let event = NSEvent.keyEvent(
                        with: type,
                        location: .zero,
                        modifierFlags: flags,
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: windowNumber,
                        context: nil,
                        characters: characters,
                        charactersIgnoringModifiers: characters,
                        isARepeat: false,
                        keyCode: keyCode
                    ) else { continue }
                    NSApp.postEvent(event, atStart: false)
                }
                await pause(0.4)
            }

            @MainActor func near(_ a: CGFloat, _ b: CGFloat, within tolerance: CGFloat = 10) -> Bool {
                abs(a - b) <= tolerance
            }

            /// Saves a picture of the screen; a failure here is not a failure
            /// of the check, since some machines do not allow it.
            @MainActor func capture(_ name: String) async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", output.appendingPathComponent("\(name).png").path]
                guard (try? process.run()) != nil else { return }
                var waited = 0.0
                while process.isRunning, waited < 6 {
                    await pause(0.2)
                    waited += 0.2
                }
                if process.isRunning { process.terminate() }
            }

            try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            showDesktopStandIn()
            await pause(0.5)

            // 1. Opening from the menu bar: visible, focused, tiles laid out.
            overlay.showPinned()
            await pause(1.0)
            let frames = tileFrames()
            let panelSize = (overlay.snapshot()["panelFrame"] as? [Double])
                .map { CGSize(width: $0[2], height: $0[3]) } ?? .zero
            var overlapping = false
            for i in frames.indices {
                for j in frames.indices where j > i && frames[i].intersects(frames[j]) {
                    overlapping = true
                }
            }
            expect("pinned", [
                ("overlay is visible", flag("visible") && flag("panelOnScreen")),
                ("overlay is interactive", flag("interactive")),
                ("panel has keyboard focus", flag("panelIsKey")),
                ("panel covers a screen", panelSize.width >= 640 && panelSize.height >= 480),
                ("board has three tiles", frames.count == 3),
                ("tiles have a usable size", frames.allSatisfy { $0.width >= 100 && $0.height >= 80 }),
                ("tiles do not overlap", !overlapping),
                ("tiles are inside the panel", frames.allSatisfy {
                    $0.minX >= 0 && $0.minY >= 0 && $0.maxX <= panelSize.width + 1 && $0.maxY <= panelSize.height + 1
                }),
            ])

            // 2. Inside a real page: blocking, hiding and the element picker.
            if pageURL != nil, let web = overlay.firstWebTile {
                @MainActor func js(_ expression: String) async -> String {
                    await web.evaluate("String(\(expression))")
                }

                // A marker in the page's script context disappears when a new
                // document replaces it, which tells a reload from the old page.
                @MainActor func waitForPage() async -> Bool {
                    for _ in 0..<80 {
                        let state = await js("document.readyState + '|' + document.title + '|' + (window.selfCheckSeen === true)")
                        if state == "complete|\(pageTitle)|false" {
                            _ = await js("window.selfCheckSeen = true")
                            return true
                        }
                        await pause(0.25)
                    }
                    return false
                }

                @MainActor func display(_ selector: String) async -> String {
                    await js("getComputedStyle(document.querySelector('\(selector)')).display")
                }

                let loaded = await waitForPage()
                let values = [
                    "allowed": await js("document.getElementById('allowed').naturalWidth"),
                    "blocked": await js("document.getElementById('blocked').naturalWidth"),
                    "banner": await display("#onetrust-consent-sdk"),
                    "adSlot": await display("ins.adsbygoogle"),
                    "customFilter": await display(".custom-hidden"),
                    "bodyText": await display("#body-text"),
                ]
                expect("page", [
                    ("the page loaded", loaded),
                    ("WebKit accepted the built-in and the custom rules",
                     overlay.ruleListCount == 2 && overlay.customFilterError == nil),
                    ("an image from the page's own site loads", values["allowed"] == "1"),
                    ("an image from a blocked host does not", values["blocked"] == "0"),
                    ("the cookie banner is hidden", values["banner"] == "none"),
                    ("the empty ad slot is hidden", values["adSlot"] == "none"),
                    ("the custom filter applies", values["customFilter"] == "none"),
                    ("ordinary content is untouched", values["bodyText"] == "block"),
                ])
                snapshots["pageValues"] = values
                await capture("page")

                // Click the headline as a person would, in "hide elements" mode.
                web.startPicker()
                await pause(0.4)
                let pickerRunning = web.isPicking
                _ = await js("""
                (function () {
                  var element = document.getElementById('headline');
                  var rect = element.getBoundingClientRect();
                  var options = {
                    bubbles: true, cancelable: true, view: window,
                    clientX: rect.left + rect.width / 2, clientY: rect.top + rect.height / 2
                  };
                  element.dispatchEvent(new MouseEvent('mousemove', options));
                  element.dispatchEvent(new MouseEvent('click', options));
                  return 'clicked';
                })()
                """)
                await pause(0.6)
                let hiddenNow = await display("#headline")
                let saved = model.workspace.boards.flatMap(\.tiles).contains { tile in
                    guard case .web(let content) = tile.content else { return false }
                    return content.hiddenElements.contains(HiddenElement(host: "127.0.0.1", selector: "h1#headline"))
                }
                web.stopPicker()
                expect("picker", [
                    ("hide-elements mode starts", pickerRunning),
                    ("the clicked element disappears", hiddenNow == "none"),
                    ("the choice is saved for that site", saved),
                    ("hide-elements mode ends", !web.isPicking),
                ])

                // The saved choice must hold on the next load, not just now.
                web.reload()
                let reloaded = await waitForPage()
                let hiddenAfterReload = await display("#headline")
                expect("reloaded", [
                    ("the page reloads", reloaded),
                    ("the element stays hidden after a reload", hiddenAfterReload == "none"),
                    ("the rest of the page is still there", await display("#body-text") == "block"),
                ])

                // Typing reaches the page while the overlay has focus.
                web.focusPage()
                _ = await js("document.getElementById('field').focus()")
                await press("g", keyCode: 5)
                await press("o", keyCode: 31)
                let typed = await js("document.getElementById('field').value")
                expect("typing", [("keys typed into a page field arrive", typed == "go")])
                snapshots["typed"] = typed

                // Signing in through a pop-up, as "Sign in with Google" does:
                // the page opens a window, which reports back and closes.
                _ = await js("document.getElementById('signin').click(), 'clicked'")
                var popup: PopupWindow?
                for _ in 0..<20 where popup == nil {
                    await pause(0.25)
                    popup = web.popups.first
                }
                var popupTitle = ""
                for _ in 0..<40 {
                    popupTitle = await popup?.evaluate("document.readyState === 'complete' ? document.title : ''") ?? ""
                    if !popupTitle.isEmpty { break }
                    await pause(0.25)
                }
                let overlayLevel = overlay.snapshot()["panelLevel"] as? Int ?? 0
                let opened: [(String, Bool)] = [
                    ("the page's pop-up opens in a window of its own", popup != nil),
                    ("it shows above the overlay", (popup?.panel.isVisible ?? false) && (popup?.panel.level.rawValue ?? 0) > overlayLevel),
                    ("it has the keyboard", popup?.panel.isKeyWindow ?? false),
                    ("its title names the site", popup?.panel.title == "127.0.0.1"),
                    ("it loads the sign-in page", popupTitle == "Sign in"),
                    ("the tile stays on its own page", await js("document.title") == pageTitle),
                ]
                await capture("popup")
                _ = await popup?.evaluate("document.getElementById('done').click(), 'done'")
                for _ in 0..<20 where !web.popups.isEmpty {
                    await pause(0.25)
                }
                await pause(0.3)
                let signedIn = await js("document.documentElement.dataset.signedIn")
                expect("popup", opened + [
                    ("the page hears back from it", signedIn == "yes"),
                    ("it closes when the page closes it", web.popups.isEmpty && !(popup?.panel.isVisible ?? false)),
                    ("the overlay has the keyboard again", flag("panelIsKey")),
                ])
                snapshots["popupValues"] = ["title": popupTitle, "signedIn": signedIn]

                // Hovering a tile brings up its controls. Blink samples where
                // the pointer is, so put the real pointer there.
                // (The web tile is the last one on the board at this point.)
                if let webFrame = tileFrames().last {
                    @MainActor func controls() -> [CGRect] {
                        let tiles = overlay.snapshot()["tiles"] as? [[String: Any]] ?? []
                        return tiles.compactMap { tile in
                            guard let frame = tile["controls"] as? [Double], frame.count == 4 else { return nil }
                            return CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3])
                        }
                    }
                    // Board coordinates and global display coordinates agree
                    // when the overlay covers the main display.
                    @MainActor func movePointer(to point: CGPoint) async {
                        CGWarpMouseCursorPosition(point)
                        await pause(0.5)
                    }

                    await movePointer(to: CGPoint(x: webFrame.midX, y: webFrame.midY))
                    let shown = controls()
                    await capture("hover")
                    var reloadedByButton = false
                    if let bar = shown.first {
                        // Back, forward, reload, more: the third button.
                        let reloadX = bar.minX + TileChromeView.inset + 2.5 * TileChromeView.buttonSize
                        await click(at: CGPoint(x: reloadX, y: bar.midY))
                        reloadedByButton = await waitForPage()
                    }
                    // Does pointer movement reach the page itself (for its own
                    // hover effects)? Recorded rather than required: it needs
                    // the pointer to really travel, which only some
                    // environments let an app do.
                    if CGPreflightPostEventAccess() {
                        for step in 1...10 {
                            let point = CGPoint(x: webFrame.minX + 20 + CGFloat(step) * 12, y: webFrame.midY + CGFloat(step) * 6)
                            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
                                .post(tap: .cghidEventTap)
                            await pause(0.05)
                        }
                        await pause(0.4)
                        snapshots["pointerMovesSeenByPage"] = await js("document.documentElement.dataset.moves || 0")
                    }

                    // Park the pointer in the margin, off every tile.
                    await movePointer(to: CGPoint(x: 4, y: panelSize.height - 4))
                    expect("hover", [
                        ("hovering a web tile shows its controls", shown.count == 1 && webFrame.contains(shown[0])),
                        ("the reload button reloads the page", reloadedByButton),
                        ("moving away hides the controls again", controls().isEmpty),
                    ])
                }
            } else {
                // No fixture server: just give the default page time to load.
                await pause(5.0)
                await capture("page")
            }

            // 3. Arranging, with the keyboard and mouse a person would use.
            await press("e", keyCode: 14, flags: .command)
            expect("editing", [("⌘E turns edit mode on", flag("editing"))])
            await capture("editing")

            // Drag the first tile past the end of the row: it becomes the last column.
            let kindsBefore = tileKinds()
            let idsBefore = tileIDs()
            let layout = framesByID()
            if let first = idsBefore.first.flatMap({ layout[$0] }),
               let last = idsBefore.last.flatMap({ layout[$0] }) {
                await drag(
                    from: CGPoint(x: first.midX, y: first.midY),
                    to: CGPoint(x: last.maxX - 10, y: last.midY)
                )
            }
            expect("reordered", [
                ("dragging a tile past the others moves it to the end",
                 tileKinds() == Array(kindsBefore.dropFirst()) + kindsBefore.prefix(1)),
                ("no tile was lost", Set(tileIDs()) == Set(idsBefore)),
            ])

            @MainActor func tileID(ofKind kind: String) -> String? {
                zip(tileIDs(), tileKinds()).first { $0.1 == kind }?.0
            }

            /// Every tile's content and arranging cover fill the tile exactly.
            @MainActor func insidesMatch() -> Bool {
                let tiles = overlay.snapshot()["tiles"] as? [[String: Any]] ?? []
                return !tiles.isEmpty && tiles.allSatisfy { $0["insideMatches"] as? Bool == true }
            }

            expect("reordered-insides", [("after dragging, every tile's inside fills the tile", insidesMatch())])

            // Stacking: drop the clock in the empty space under the note, and
            // it goes into the note's column, below it.
            if let notes = tileID(ofKind: "widget:notes"), let clock = tileID(ofKind: "widget:clock"),
               let notesFrame = framesByID()[notes], let clockFrame = framesByID()[clock] {
                await drag(
                    from: CGPoint(x: clockFrame.midX, y: clockFrame.midY),
                    to: CGPoint(x: notesFrame.midX, y: notesFrame.maxY + 80)
                )
                let frames = framesByID()
                let top = frames[notes] ?? .zero, below = frames[clock] ?? .zero
                expect("stacked", [
                    ("a tile dropped under another joins its column",
                     near(below.minX, top.minX, within: 1) && near(below.width, top.width, within: 1)),
                    ("and sits below it", below.minY > top.maxY && below.minY < top.maxY + 40),
                    ("each keeps its own height", near(top.height, notesFrame.height, within: 1)
                        && near(below.height, clockFrame.height, within: 1)),
                    ("every tile's inside fills the tile", insidesMatch()),
                ])
                await capture("stacked")

                // The edge between them sizes the tile above; the one below follows.
                await drag(
                    from: CGPoint(x: top.midX, y: top.maxY - 4),
                    to: CGPoint(x: top.midX, y: top.maxY - 104)
                )
                let after = framesByID()
                expect("stack-resized", [
                    ("pulling the edge up makes the upper tile shorter",
                     near(after[notes]?.height ?? 0, top.height - 100, within: 3)),
                    ("and the tile below moves up with it",
                     near(after[clock]?.minY ?? 0, below.minY - 100, within: 3)),
                    ("and keeps its height", near(after[clock]?.height ?? 0, below.height, within: 1)),
                ])
            }

            // A tile on its own can be made shorter too, leaving room below it.
            if let web = tileID(ofKind: "web"), let before = framesByID()[web] {
                await drag(
                    from: CGPoint(x: before.midX, y: before.maxY - 4),
                    to: CGPoint(x: before.midX, y: before.maxY - 154)
                )
                let after = framesByID()[web] ?? .zero
                expect("shortened", [
                    ("pulling a lone tile's bottom edge up makes it shorter", near(after.height, before.height - 150, within: 3)),
                    ("its top stays put", near(after.minY, before.minY, within: 1)),
                    ("every tile's inside fills the tile", insidesMatch()),
                ])
                await capture("shortened")
            }

            // The top edge works the other way round: the bottom stays put
            // and the top comes down, leaving space above the tile.
            if let web = tileID(ofKind: "web"), let before = framesByID()[web] {
                await drag(
                    from: CGPoint(x: before.midX, y: before.minY + 4),
                    to: CGPoint(x: before.midX, y: before.minY + 104)
                )
                let after = framesByID()[web] ?? .zero
                expect("top-edge", [
                    ("pulling the top edge down moves the top down", near(after.minY, before.minY + 100, within: 3)),
                    ("and keeps the bottom where it was", near(after.maxY, before.maxY, within: 2)),
                    ("every tile's inside fills the tile", insidesMatch()),
                ])
                await capture("top-edge")
            }

            // Resizing: pull a tile's right edge out by 60 points. The row of
            // columns stays centred, so the tile widens by up to twice that;
            // less on a narrow screen, where the whole row is squeezed to fit.
            if let id = tileIDs().first, let before = framesByID()[id] {
                await drag(
                    from: CGPoint(x: before.maxX - 5, y: before.midY),
                    to: CGPoint(x: before.maxX + 55, y: before.midY)
                )
                let resized = framesByID()[id] ?? .zero
                expect("resized", [
                    ("dragging the right edge widens the tile", resized.width > before.width + 30),
                    ("the height is unchanged", near(resized.height, before.height, within: 1)),
                    ("every tile is still on the board", Set(tileIDs()) == Set(idsBefore)),
                ])
                await capture("resized")

                // Its remove button takes it off the board.
                let countBefore = tileIDs().count
                let remove = TileEditCover.removeButtonFrame
                await click(at: CGPoint(x: resized.minX + remove.midX, y: resized.minY + remove.midY))
                expect("removed", [
                    ("the remove button removes the tile", tileIDs().count == countBefore - 1 && !tileIDs().contains(id)),
                ])
            }

            // Escape backs out one step at a time: first out of edit mode.
            await press("\u{1b}", keyCode: 53)
            expect("escape-editing", [
                ("esc leaves edit mode", !flag("editing")),
                ("and keeps the overlay open", flag("visible")),
            ])

            // 4. The launcher, and adding a tile from it.
            await press("n", keyCode: 45, flags: .command)
            expect("launcher", [("⌘N opens the launcher", flag("launcherOpen"))])
            await capture("launcher")
            await press("\u{1b}", keyCode: 53)
            expect("escape-launcher", [
                ("esc closes the launcher", !flag("launcherOpen")),
                ("and keeps the overlay open", flag("visible")),
            ])

            // Typing filters the list; Return adds the best match.
            let countBeforeAdding = tileIDs().count
            await press("n", keyCode: 45, flags: .command)
            await press("c", keyCode: 8)
            await press("a", keyCode: 0)
            await press("l", keyCode: 37)
            await capture("launcher-search")
            await press("\r", keyCode: 36)
            await pause(0.4)
            expect("added-by-typing", [
                ("typing \"cal\" and pressing Return adds the Calendar widget", tileKinds().contains("widget:calendar")),
                ("exactly one tile was added", tileIDs().count == countBeforeAdding + 1),
                ("adding closes the launcher", !flag("launcherOpen")),
            ])

            // The arrow keys move through the list: the third row is Reminders.
            await press("n", keyCode: 45, flags: .command)
            await press("\u{F701}", keyCode: 125)
            await press("\u{F701}", keyCode: 125)
            await press("\r", keyCode: 36)
            await pause(0.4)
            expect("added-by-arrows", [
                ("two presses of ↓ and Return add the third item", tileKinds().contains("widget:reminders")),
                ("exactly one more tile was added", tileIDs().count == countBeforeAdding + 2),
            ])

            // 5. Dismissing with the keyboard.
            await press("\u{1b}", keyCode: 53)
            await pause(0.4)
            expect("dismissed", [
                ("esc closes the overlay", !flag("visible") && !flag("panelOnScreen")),
                ("overlay is no longer interactive", !flag("interactive")),
            ])

            // 6. Hold: visible only while the shortcut is down.
            overlay.shortcutDown()
            await pause(1.2)
            expect("holding", [
                ("holding shows the overlay", flag("visible") && flag("panelOnScreen")),
                ("a held overlay does not take focus", !flag("interactive") && !flag("panelIsKey")),
            ])
            await capture("holding")
            overlay.shortcutUp()
            await pause(0.6)
            expect("released", [("releasing hides the overlay", !flag("visible") && !flag("panelOnScreen"))])

            // 7. Tap: stays open, and the next press closes it.
            overlay.shortcutDown()
            await pause(0.02)
            overlay.shortcutUp()
            await pause(0.5)
            expect("tapped", [("a tap keeps the overlay open", flag("visible") && flag("interactive"))])
            overlay.shortcutDown()
            overlay.shortcutUp()
            await pause(0.6)
            expect("tapped-again", [("tapping again closes it", !flag("visible") && !flag("panelOnScreen"))])

            // 8. Local files, opened the way Finder's "Open With" hands them over.
            if let fixtures = ProcessInfo.processInfo.environment["BLINK_SMOKE_FIXTURES"] {
                let folder = URL(fileURLWithPath: fixtures, isDirectory: true)
                model.update { workspace in
                    workspace.updateBoard(workspace.sharedBoardID) { $0.tiles = [] }
                }
                overlay.addFiles([
                    folder.appendingPathComponent("sample.pdf"),
                    folder.appendingPathComponent("page.html"),
                    folder.appendingPathComponent("notes.txt"),  // not a kind Blink shows
                ])
                await pause(2.0)
                expect("files", [
                    ("adding files opens the overlay", flag("visible") && flag("interactive")),
                    ("the PDF and the HTML file each get a tile", tileKinds() == ["file", "file"]),
                ])
                await capture("files")
            }

            // 9. Calendar and Reminders, fed with stand-in data.
            EventKitService.shared.useSampleData(sampleData())
            model.update { workspace in
                workspace.updateBoard(workspace.sharedBoardID) { board in
                    board.tiles = [
                        Tile(content: .widget(.calendar(CalendarConfig(mode: .day)))),
                        Tile(content: .widget(.calendar(CalendarConfig(mode: .agenda)))),
                        Tile(content: .widget(.reminders(RemindersConfig(filter: .today)))),
                        Tile(content: .widget(.reminders(RemindersConfig(filter: .all)))),
                    ]
                }
            }
            overlay.showPinned()
            await pause(1.5)
            expect("widgets", [("the four widgets are laid out", tileKinds().count == 4 && flag("visible"))])
            await capture("widgets")

            // A typical board, for a picture of what Blink looks like in use.
            if let pageURL {
                var dashboard = Tile(content: .web(WebContent(
                    url: pageURL.deletingLastPathComponent().appendingPathComponent("dashboard.html")
                )))
                dashboard.flowWidth = 400
                model.update { workspace in
                    workspace.updateBoard(workspace.sharedBoardID) { board in
                        let clock = Tile(content: .widget(.clock(ClockConfig(zones: [ClockConfig.localZone, "Europe/London", "Asia/Tokyo"]))))
                        // Reminders stacked under the clock, taking the rest of the column.
                        var reminders = Tile(content: .widget(.reminders(RemindersConfig(filter: .today))))
                        reminders.column = clock.column
                        reminders.flowHeight = nil
                        board.tiles = [
                            clock,
                            reminders,
                            dashboard,
                            Tile(content: .widget(.calendar(CalendarConfig(mode: .day)))),
                        ]
                    }
                }
                await pause(3.0)
                expect("showcase", [("the showcase board is laid out", tileKinds().count == 4 && flag("visible"))])
                await capture("showcase")
            }

            // Messages, fed with stand-in conversations: the list, then a thread.
            MessagesService.shared.useSampleData(sampleMessages())
            model.update { workspace in
                workspace.updateBoard(workspace.sharedBoardID) { board in
                    board.tiles = [Tile(content: .widget(.messages(MessagesConfig())))]
                }
            }
            overlay.showPinned()
            await pause(1.0)
            expect("messages", [("the Messages widget is on the board", tileKinds() == ["widget:messages"])])
            await capture("messages")
            if let messages = framesByID().values.first {
                // The first conversation, just under the list's heading.
                await click(at: CGPoint(x: messages.midX, y: messages.minY + 62))
                await pause(0.8)
                await capture("messages-thread")
            }

            // 10. A layout per display starts as a copy and then goes its own way.
            let sharedIDs = Set(tileIDs())
            overlay.dismiss()
            await pause(0.5)
            model.updateSettings { $0.syncAcrossDisplays = false }
            overlay.showPinned()
            await pause(1.0)
            let ownIDs = Set(tileIDs())
            overlay.addTile(.widget(.notes(NotesConfig(text: "Only on this display"))))
            await pause(0.5)
            let ownCount = tileIDs().count
            overlay.dismiss()
            await pause(0.5)
            model.updateSettings { $0.syncAcrossDisplays = true }
            overlay.showPinned()
            await pause(1.0)
            expect("per-display", [
                ("a display's own layout starts with the same tiles", ownIDs.count == sharedIDs.count),
                ("but as separate copies", ownIDs.isDisjoint(with: sharedIDs)),
                ("changes to it stay on that display", ownCount == sharedIDs.count + 1 && Set(tileIDs()) == sharedIDs),
            ])
            overlay.dismiss()
            await pause(0.5)

            // Timings, for the report rather than as pass or fail: how long the
            // main thread is busy opening the overlay, and with each keystroke
            // in a note (each one is saved to the layout).
            func milliseconds(_ body: () -> Void) -> Double {
                let start = DispatchTime.now().uptimeNanoseconds
                body()
                return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            }
            func median(_ values: [Double]) -> Double {
                let sorted = values.sorted()
                return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
            }
            func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }

            var opens: [Double] = []
            for _ in 0..<8 {
                opens.append(milliseconds { overlay.showPinned() })
                await pause(0.4)
                overlay.dismiss()
                await pause(0.4)
            }

            // With a long list of filters of one's own, as some people paste in.
            let ownFilters = model.settings.customFilters
            let longList = (0..<3000).map { "||ads\($0).example.com^" }.joined(separator: "\n")
            model.updateSettings { $0.customFilters = longList }
            let boardID = model.workspace.sharedBoardID
            let note = Tile(content: .widget(.notes(NotesConfig(text: ""))))
            model.update { $0.addTile(note, to: boardID) }
            overlay.showPinned()
            await pause(1.0)
            var keystrokes: [Double] = []
            var typed = ""
            for character in "Call Sam about the launch" {
                typed.append(character)
                let text = typed
                keystrokes.append(milliseconds {
                    model.updateTile(note.id, in: boardID) { $0.content = .widget(.notes(NotesConfig(text: text))) }
                })
                await pause(0.03)
            }
            // What each keystroke used to cost on top: building the blocking
            // rules again from scratch.
            let settings = model.settings
            let rebuild = milliseconds {
                _ = ContentBlocker.encode(ContentBlocker.builtInRules(for: settings.contentBlocking))
                _ = ContentBlocker.encode(FilterListParser.parse(settings.customFilters).rules)
            }
            model.update { $0.removeTile(note.id, from: boardID) }
            model.updateSettings { $0.customFilters = ownFilters }
            overlay.dismiss()
            await pause(0.5)
            performance = [
                "openMedianMs": rounded(median(opens)),
                "openMaxMs": rounded(opens.max() ?? 0),
                "keystrokeMedianMs": rounded(median(keystrokes)),
                "keystrokeMaxMs": rounded(keystrokes.max() ?? 0),
                "ruleRebuildNoLongerPerKeystrokeMs": rounded(rebuild),
            ]

            // 11. The settings window.
            overlay.onOpenSettings?()
            await pause(1.5)
            expect("settings", [
                ("the settings window opens", NSApp.windows.contains { $0.title == "Blink Settings" && $0.isVisible }),
                ("the overlay is out of its way", !flag("visible")),
            ])
            await capture("settings")

            // 12. Updating. The script that runs this publishes stand-in
            // releases on a local server and runs a copy of the app, so that
            // the copy can replace itself for real.
            var update: [String: Any] = ["checked": false]
            if !updater.source.isOfficial {
                update["checked"] = true
                update["running"] = updater.currentText
                let versionOnDisk = {
                    let plist = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")
                    return NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String ?? "unreadable"
                }

                // Releases that must be turned away, leaving this copy as it was.
                var refusals: [String: String] = [:]
                let rejected = (ProcessInfo.processInfo.environment["BLINK_SMOKE_REJECTED_FEEDS"] ?? "")
                    .split(separator: ",").compactMap { URL(string: String($0)) }
                for feed in rejected {
                    let name = feed.deletingPathExtension().lastPathComponent
                    let other = Updater(feed: feed)
                    guard case .available(let offer) = await other.check() else {
                        failures.append("update: the \(name) release was not even offered")
                        continue
                    }
                    do {
                        try await other.install(offer, relaunch: false)
                        failures.append("update: the \(name) release was installed")
                    } catch {
                        refusals[name] = error.localizedDescription
                    }
                    if versionOnDisk() != updater.currentText {
                        failures.append("update: refusing the \(name) release still changed the app")
                    }
                }
                update["refused"] = refusals

                // And one that should go in.
                let found = await updater.check()
                if case .available(let offer) = found {
                    update["offered"] = offer.versionText
                    do {
                        try await updater.install(offer, relaunch: false)
                        update["installed"] = versionOnDisk()
                        if versionOnDisk() != offer.versionText {
                            failures.append("update: the app on disk is \(versionOnDisk()), not \(offer.versionText)")
                        }
                    } catch {
                        update["error"] = error.localizedDescription
                        failures.append("update: installing failed: \(error.localizedDescription)")
                    }
                } else {
                    failures.append("update: a newer release was published but not offered (\(found))")
                }
            }

            let report: [String: Any] = [
                "ok": failures.isEmpty,
                "failures": failures,
                "checkedPage": pageURL != nil,
                // With this on, macOS draws glass as a flat colour, which
                // explains screenshots that show no blur.
                "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                "hotkey": String(describing: hotkeys.status),
                "shortcut": hotkeys.shortcut.displayString,
                "update": update,
                "performance": performance,
                "snapshots": snapshots,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: output.appendingPathComponent("smoke.json"))
            }
            for failure in failures {
                FileHandle.standardError.write(Data("FAILED \(failure)\n".utf8))
            }
            print(failures.isEmpty ? "Self-check passed." : "Self-check failed: \(failures.count) problem(s).")
            exit(failures.isEmpty ? 0 : 1)
        }
    }
}
