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
            } else {
                // No fixture server: just give the default page time to load.
                await pause(5.0)
                await capture("page")
            }

            // 3. Arranging.
            overlay.setEditing(true)
            await pause(0.4)
            expect("editing", [("edit mode is on", flag("editing"))])
            await capture("editing")

            let flowFrames = tileFrames()
            overlay.setLayoutMode(.freeform)
            await pause(0.6)
            let freeformFrames = tileFrames()
            let stayedPut = flowFrames.count == freeformFrames.count && zip(flowFrames, freeformFrames).allSatisfy { a, b in
                abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2
                    && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
            }
            expect("freeform", [
                ("the board is in freeform mode", overlay.snapshot()["mode"] as? String == "freeform"),
                ("switching mode leaves tiles where they were", stayedPut),
            ])
            overlay.setLayoutMode(.flow)
            await pause(0.6)
            expect("flow", [("the board is back in flow mode", overlay.snapshot()["mode"] as? String == "flow")])

            // 4. The launcher, and adding a tile from it.
            overlay.presentLauncher()
            await pause(0.5)
            expect("launcher", [
                ("launcher is open", flag("launcherOpen")),
                ("opening the launcher leaves edit mode", !flag("editing")),
            ])
            await capture("launcher")

            overlay.addTile(.widget(.clock(ClockConfig())))
            await pause(0.6)
            expect("added", [
                ("the new tile appears", tileFrames().count == 4),
                ("adding closes the launcher", !flag("launcherOpen")),
            ])

            // 5. Dismissing.
            overlay.dismiss()
            await pause(0.6)
            expect("dismissed", [
                ("overlay is hidden", !flag("visible") && !flag("panelOnScreen")),
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
