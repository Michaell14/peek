import AppKit
import GanderCore

/// An end-to-end self-check: drives the real overlay through its main states
/// and writes what it saw to `smoke.json`. Run with `--smoke-test <dir>`.
///
/// It uses an in-memory workspace, so it never touches a real layout.
@MainActor
enum SmokeTest {
    static func run(model: AppModel, overlay: OverlayController, hotkeys: HotkeyMonitor, output: URL) {
        // A generous tap window keeps a busy machine from turning the tap
        // below into a hold.
        model.updateSettings { $0.tapThreshold = 0.6 }
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

            try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            await pause(0.5)

            // 1. Opening from the menu bar: visible, focused, tiles laid out.
            overlay.showPinned()
            await pause(1.0)
            let frames = tileFrames()
            let panelSize = (overlay.snapshot()["panelFrame"] as? [Double]).map { CGSize(width: $0[2], height: $0[3]) } ?? .zero
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
                ("default board has three tiles", frames.count == 3),
                ("tiles have a usable size", frames.allSatisfy { $0.width >= 100 && $0.height >= 80 }),
                ("tiles do not overlap", !overlapping),
                ("tiles are inside the panel", frames.allSatisfy {
                    $0.minX >= 0 && $0.minY >= 0 && $0.maxX <= panelSize.width + 1 && $0.maxY <= panelSize.height + 1
                }),
            ])

            // Give the web tile time to load, then keep a picture of it.
            await pause(5.0)
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", output.appendingPathComponent("screen.png").path]
            if (try? capture.run()) != nil {
                // Never let a stuck screenshot hold up the check itself.
                var waited = 0.0
                while capture.isRunning, waited < 6 {
                    await pause(0.2)
                    waited += 0.2
                }
                if capture.isRunning { capture.terminate() }
            }

            // 2. Arranging and the launcher.
            overlay.setEditing(true)
            expect("editing", [("edit mode is on", flag("editing"))])
            overlay.presentLauncher()
            await pause(0.3)
            expect("launcher", [
                ("launcher is open", flag("launcherOpen")),
                ("opening the launcher leaves edit mode", !flag("editing")),
            ])

            // 3. Adding a tile.
            overlay.addTile(.widget(.notes(NotesConfig(text: "self-check"))))
            await pause(0.5)
            expect("added", [
                ("the new tile appears", tileFrames().count == 4),
                ("adding closes the launcher", !flag("launcherOpen")),
            ])

            // 4. Dismissing.
            overlay.dismiss()
            await pause(0.6)
            expect("dismissed", [
                ("overlay is hidden", !flag("visible") && !flag("panelOnScreen")),
                ("overlay is no longer interactive", !flag("interactive")),
            ])

            // 5. Hold: visible only while the shortcut is down.
            overlay.shortcutDown()
            await pause(1.2)
            expect("holding", [
                ("holding shows the overlay", flag("visible") && flag("panelOnScreen")),
                ("a held overlay does not take focus", !flag("interactive")),
            ])
            overlay.shortcutUp()
            await pause(0.6)
            expect("released", [("releasing hides the overlay", !flag("visible") && !flag("panelOnScreen"))])

            // 6. Tap: stays open, and the next press closes it.
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
