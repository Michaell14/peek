import AppKit
import GanderCore

/// An end-to-end self-check: drives the real overlay through its main states
/// and writes what it saw to `smoke.json`, with screenshots alongside.
///
///     Gander --smoke-test <output directory>
///
/// If `GANDER_SMOKE_URL` points at `Tests/Fixtures/page.html` served over
/// HTTP, it also checks content blocking and element hiding inside a real
/// page. It uses an in-memory workspace, so it never touches a real layout.
@MainActor
enum SmokeTest {
    private static let pageTitle = "Gander self-check page"

    static func run(model: AppModel, overlay: OverlayController, hotkeys: HotkeyMonitor, output: URL) {
        let pageURL = ProcessInfo.processInfo.environment["GANDER_SMOKE_URL"].flatMap(URL.init(string:))

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
            } else {
                // No fixture server: just give the default page time to load.
                await pause(5.0)
                await capture("page")
            }

            // 3. Arranging, with the keyboard and mouse a person would use.
            await press("e", keyCode: 14, flags: .command)
            expect("editing", [("⌘E turns edit mode on", flag("editing"))])
            await capture("editing")

            // Flow: drag the first tile past the last one to reorder.
            let kindsBefore = tileKinds()
            let idsBefore = tileIDs()
            var layout = framesByID()
            if let first = idsBefore.first.flatMap({ layout[$0] }),
               let last = idsBefore.last.flatMap({ layout[$0] }) {
                await drag(
                    from: CGPoint(x: first.midX, y: first.midY),
                    to: CGPoint(x: last.maxX - 20, y: last.midY)
                )
            }
            expect("reordered", [
                ("dragging a tile past the others moves it to the end",
                 tileKinds() == Array(kindsBefore.dropFirst()) + kindsBefore.prefix(1)),
                ("no tile was lost", Set(tileIDs()) == Set(idsBefore)),
            ])

            // Freeform: the switch keeps tiles in place, then resize and move.
            let flowFrames = framesByID()
            overlay.setLayoutMode(.freeform)
            await pause(0.6)
            layout = framesByID()
            let stayedPut = flowFrames.count == layout.count && flowFrames.allSatisfy { id, before in
                guard let after = layout[id] else { return false }
                return near(before.minX, after.minX, within: 2) && near(before.minY, after.minY, within: 2)
                    && near(before.width, after.width, within: 2) && near(before.height, after.height, within: 2)
            }
            expect("freeform", [
                ("the board is in freeform mode", overlay.snapshot()["mode"] as? String == "freeform"),
                ("switching mode leaves tiles where they were", stayedPut),
            ])

            if let id = tileIDs().first, let before = layout[id] {
                // Pull the bottom edge up by 200 points.
                await drag(
                    from: CGPoint(x: before.midX, y: before.maxY - 5),
                    to: CGPoint(x: before.midX, y: before.maxY - 205)
                )
                let resized = framesByID()[id] ?? .zero
                expect("resized", [
                    ("dragging the bottom edge changes the height", near(resized.height, before.height - 200)),
                    ("the top edge stays put", near(resized.minY, before.minY, within: 1)),
                    ("the width is unchanged", near(resized.width, before.width, within: 1)),
                ])

                // Then drag it by its middle.
                await drag(
                    from: CGPoint(x: resized.midX, y: resized.midY),
                    to: CGPoint(x: resized.midX + 60, y: resized.midY + 40)
                )
                let moved = framesByID()[id] ?? .zero
                expect("moved", [
                    ("dragging the middle moves the tile", near(moved.minX, resized.minX + 60) && near(moved.minY, resized.minY + 40)),
                    ("moving does not resize", near(moved.width, resized.width, within: 1) && near(moved.height, resized.height, within: 1)),
                ])
                await capture("freeform")

                // Its remove button takes it off the board.
                let countBefore = tileIDs().count
                await click(at: CGPoint(x: moved.minX + 22, y: moved.minY + 22))
                expect("removed", [
                    ("the remove button removes the tile", tileIDs().count == countBefore - 1 && !tileIDs().contains(id)),
                ])
            }

            // Back to flow: the tiles that were not touched return to
            // exactly where flow had them.
            let beforeFlow = framesByID()
            overlay.setLayoutMode(.flow)
            await pause(0.6)
            let afterFlow = framesByID()
            let untouched = afterFlow.keys.filter { flowFrames[$0] != nil }
            expect("flow", [
                ("the board is back in flow mode", overlay.snapshot()["mode"] as? String == "flow"),
                ("every remaining tile is still on the board", Set(afterFlow.keys) == Set(beforeFlow.keys)),
                ("tiles keep their heights and vertical positions", untouched.allSatisfy { id in
                    guard let was = flowFrames[id], let now = afterFlow[id] else { return false }
                    return near(was.minY, now.minY, within: 2) && near(was.height, now.height, within: 2)
                }),
            ])

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

            let countBeforeAdding = tileIDs().count
            overlay.presentLauncher()
            await pause(0.3)
            overlay.addTile(.widget(.clock(ClockConfig())))
            await pause(0.6)
            expect("added", [
                ("the new tile appears", tileIDs().count == countBeforeAdding + 1),
                ("adding closes the launcher", !flag("launcherOpen")),
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

            let report: [String: Any] = [
                "ok": failures.isEmpty,
                "failures": failures,
                "checkedPage": pageURL != nil,
                "hotkey": String(describing: hotkeys.status),
                "shortcut": hotkeys.shortcut.displayString,
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
