import Foundation

/// Reads and writes the workspace as a JSON file.
public struct WorkspaceStore: Sendable {
    public enum LoadResult: Sendable {
        case loaded(Workspace)
        /// Nothing saved yet.
        case missing
        /// The file exists but could not be read. It was moved to `backup`
        /// rather than overwritten, so nothing the user built is lost.
        case corrupt(backup: URL?)
    }

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(directory: URL) {
        self.init(fileURL: directory.appendingPathComponent("workspace.json"))
    }

    public func load() -> LoadResult {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else { return .missing }
        do {
            let data = try Data(contentsOf: fileURL)
            return .loaded(try JSONDecoder().decode(Workspace.self, from: data))
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("workspace.unreadable-\(stamp).json")
            do {
                try manager.moveItem(at: fileURL, to: backup)
                return .corrupt(backup: backup)
            } catch {
                return .corrupt(backup: nil)
            }
        }
    }

    public func save(_ workspace: Workspace) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(workspace)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
