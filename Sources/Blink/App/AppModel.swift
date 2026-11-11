import AppKit
import Combine
import BlinkCore

/// The single source of truth for layouts and settings. Views read
/// `workspace` and change it only through `update`, which also saves.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var workspace: Workspace

    let directory: URL
    /// Set when the saved workspace could not be read at launch.
    private(set) var loadWarning: String?
    /// True when there was nothing saved yet, i.e. the very first run.
    private(set) var isFirstLaunch = false

    private let store: WorkspaceStore
    private let persists: Bool
    private var saveGeneration = 0

    /// - Parameter persists: false keeps everything in memory (self-checks).
    init(directory: URL, persists: Bool = true) {
        self.directory = directory
        self.persists = persists
        store = WorkspaceStore(directory: directory)

        guard persists else {
            workspace = Workspace.makeDefault()
            return
        }
        switch store.load() {
        case .loaded(let saved):
            workspace = saved
        case .missing:
            workspace = Workspace.makeDefault()
            isFirstLaunch = true
        case .corrupt(let backup):
            workspace = Workspace.makeDefault()
            if let backup {
                loadWarning = "Your saved layout could not be read, so Blink started fresh. "
                    + "The old file was kept at \(backup.path)."
            } else {
                loadWarning = "Your saved layout could not be read, so Blink started fresh."
            }
        }
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Blink", isDirectory: true)
    }

    var settings: AppSettings { workspace.settings }

    func update(_ change: (inout Workspace) -> Void) {
        var copy = workspace
        change(&copy)
        guard copy != workspace else { return }
        workspace = copy
        scheduleSave()
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        update { change(&$0.settings) }
    }

    func updateTile(_ tileID: UUID, in boardID: UUID, _ change: (inout Tile) -> Void) {
        update { $0.updateTile(tileID, in: boardID, change) }
    }

    /// The board to show on a display, created on first use.
    func boardID(forDisplay key: String, name: String) -> UUID {
        if let existing = workspace.boardID(forDisplay: key) { return existing }
        var id = workspace.sharedBoardID
        update { id = $0.ensureBoard(forDisplay: key, name: name) }
        return id
    }

    func saveNow() {
        saveGeneration += 1
        guard persists else { return }
        do {
            try store.save(workspace)
        } catch {
            NSLog("Blink: could not save workspace: \(error.localizedDescription)")
        }
    }

    /// Coalesces bursts of changes (dragging, typing) into one write.
    private func scheduleSave() {
        saveGeneration += 1
        let generation = saveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            onMainActor {
                guard let self, self.saveGeneration == generation else { return }
                self.saveNow()
            }
        }
    }
}
