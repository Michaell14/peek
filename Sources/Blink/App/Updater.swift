import AppKit
import BlinkCore

/// Looks for a newer Blink among the project's releases on GitHub and, when
/// asked, puts it in place of the running copy.
///
/// Nothing about the person or the Mac is sent: the check is one plain
/// request for the latest release. What comes back is only installed if it
/// arrives over HTTPS from this project's own releases, is this app, is the
/// version that was offered, has an intact signature, and, when the running
/// copy was signed by an identifiable developer, was signed by the same one.
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateOffer)
        case installing(UpdateOffer)
        case failed(String)
    }

    enum InstallError: LocalizedError {
        /// The release has nothing Blink can install by itself.
        case noArchive
        /// This copy is somewhere it cannot be replaced.
        case cannotReplace(String)
        case download(String)
        case unpack(String)
        /// The download is not something Blink should run.
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .noArchive:
                return "This release has to be downloaded by hand."
            case .cannotReplace(let why), .download(let why), .unpack(let why):
                return why
            case .rejected(let why):
                return "The download was not installed because \(why)."
            }
        }
    }

    static let repository = "Michaell14/peek"
    private static let lastCheckKey = "BlinkLastUpdateCheck"
    private static let announcedKey = "BlinkAnnouncedUpdate"

    @Published private(set) var state: State = .idle

    let source: UpdateSource
    /// The running version. Nil when there is no app bundle around the
    /// program (`swift run`), which leaves nothing to compare or replace.
    let current: AppVersion?
    /// The same, as shown to people.
    let currentText: String

    private let bundleURL: URL
    private let bundleIdentifier: String
    private let defaults: UserDefaults
    private let session: URLSession

    init(feed: URL? = nil, bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        source = UpdateSource(repository: Self.repository, feed: feed)
        bundleURL = bundle.bundleURL
        bundleIdentifier = bundle.bundleIdentifier ?? ""
        self.defaults = defaults

        let text = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        currentText = text ?? "a development build"
        if bundle.bundleURL.pathExtension == "app", let text {
            current = AppVersion(text)
        } else {
            current = nil
        }

        // No cookies, no cache, nothing kept between checks.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["Accept": "application/vnd.github+json", "User-Agent": "Blink"]
        session = URLSession(configuration: configuration)
    }

    // MARK: - Checking

    /// True once a day has gone by since the last check.
    var isDue: Bool {
        UpdateCheck.isDue(lastCheck: defaults.object(forKey: Self.lastCheckKey) as? Date, now: Date())
    }

    @discardableResult
    func check() async -> State {
        if case .installing = state { return state }
        guard let current else {
            state = .failed("This is a development build, so there is no version to compare.")
            return state
        }
        state = .checking
        var request = URLRequest(url: source.feed)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request)
            defaults.set(Date(), forKey: Self.lastCheckKey)
            switch (response as? HTTPURLResponse)?.statusCode ?? 200 {
            case 200:
                let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
                if let offer = UpdateCheck.offer(from: release, current: current, source: source) {
                    state = .available(offer)
                } else {
                    state = .upToDate
                }
            case 404:
                // Nothing has been published yet.
                state = .upToDate
            case 403, 429:
                state = .failed("GitHub is limiting requests from this network. Try again in an hour.")
            case let code:
                state = .failed("GitHub answered with an error (\(code)). Try again later.")
            }
        } catch is DecodingError {
            state = .failed("The answer from GitHub could not be read.")
        } catch {
            state = .failed(error.localizedDescription)
        }
        return state
    }

    /// True the first time a given version is found, so that a check made in
    /// the background interrupts with it once rather than at every launch.
    func shouldAnnounce(_ offer: UpdateOffer) -> Bool {
        guard defaults.string(forKey: Self.announcedKey) != offer.versionText else { return false }
        defaults.set(offer.versionText, forKey: Self.announcedKey)
        return true
    }

    // MARK: - Installing

    /// Fetches the offered version, checks it, and swaps it for this copy.
    /// - Parameter relaunch: false leaves the old copy running (the checks).
    func install(_ offer: UpdateOffer, relaunch: Bool = true) async throws {
        guard let archive = offer.archive else { throw InstallError.noArchive }
        try checkCanBeReplaced()
        state = .installing(offer)
        do {
            try await fetchAndSwap(archive, offer: offer)
        } catch {
            state = .available(offer)
            throw error
        }
        if relaunch {
            relaunchAndQuit()
        } else {
            state = .upToDate
        }
    }

    private func checkCanBeReplaced() throws {
        let path = bundleURL.path
        guard bundleURL.pathExtension == "app" else {
            throw InstallError.cannotReplace("This copy of Blink is not an app that can replace itself.")
        }
        // macOS runs a freshly downloaded app from a hidden, read-only copy
        // until it has been moved somewhere by hand.
        if path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/") {
            throw InstallError.cannotReplace("Move Blink to your Applications folder first, then update from there.")
        }
        guard FileManager.default.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path) else {
            throw InstallError.cannotReplace("Blink is in a folder it is not allowed to change.")
        }
    }

    private func fetchAndSwap(_ archive: URL, offer: UpdateOffer) async throws {
        let files = FileManager.default
        // A scratch folder on the same disk as the app, so the swap is a rename.
        let work: URL
        do {
            work = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: bundleURL, create: true)
        } catch {
            throw InstallError.cannotReplace("Blink could not make room for the download: \(error.localizedDescription)")
        }
        defer { try? files.removeItem(at: work) }

        let zip = work.appendingPathComponent("Blink.zip")
        do {
            let (downloaded, response) = try await session.download(from: archive)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard code == 200 else {
                throw InstallError.download("The download failed (\(code)).")
            }
            try files.moveItem(at: downloaded, to: zip)
        } catch let error as InstallError {
            throw error
        } catch {
            throw InstallError.download("The download failed: \(error.localizedDescription)")
        }

        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        try? files.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let unzip = await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        let apps = ((try? files.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "app" }
        guard unzip.status == 0, apps.count == 1, let newApp = apps.first else {
            throw InstallError.unpack("The download could not be unpacked.")
        }

        try await verify(newApp, offer: offer)

        do {
            _ = try files.replaceItemAt(bundleURL, withItemAt: newApp)
        } catch {
            throw InstallError.cannotReplace("The new version could not be put in place: \(error.localizedDescription)")
        }
    }

    private func verify(_ app: URL, offer: UpdateOffer) async throws {
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let problem = UpdateCheck.problem(
            withIdentifier: info?["CFBundleIdentifier"] as? String,
            version: info?["CFBundleShortVersionString"] as? String,
            expecting: offer,
            identifier: bundleIdentifier
        )
        switch problem {
        case .differentApp(let found):
            throw InstallError.rejected("it is a different app (\(found))")
        case .differentVersion(let found):
            throw InstallError.rejected("it is version \(found), not \(offer.versionText)")
        case nil:
            break
        }

        // Nothing added, removed or changed since it was signed.
        let seal = await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        guard seal.status == 0 else {
            throw InstallError.rejected("it has been altered since it was signed")
        }

        // Signed by whoever signed this copy. An ad hoc signature names one
        // exact build and no developer, which leaves nothing to compare.
        if let signer = await Self.signer(of: bundleURL) {
            let match = await Self.run("/usr/bin/codesign", ["--verify", "-R", "=" + signer, app.path])
            guard match.status == 0 else {
                throw InstallError.rejected("it was not signed by the developer who signed this copy")
            }
        }
    }

    /// The requirement that says who signed the app at `url`, in codesign's
    /// own language, or nil when the signature names no one.
    private nonisolated static func signer(of url: URL) async -> String? {
        let result = await run("/usr/bin/codesign", ["-d", "-r-", url.path])
        guard result.status == 0 else { return nil }
        for line in result.output.split(separator: "\n") {
            guard let marker = line.range(of: "designated => ") else { continue }
            let requirement = String(line[marker.upperBound...])
            return requirement.contains("cdhash") ? nil : requirement
        }
        return nil
    }

    /// Starts the new copy as soon as this one has gone.
    private func relaunchAndQuit() {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        let pid = ProcessInfo.processInfo.processIdentifier
        helper.arguments = [
            "-c",
            "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
            bundleURL.path,
        ]
        try? helper.run()
        NSApp.terminate(nil)
    }

    // MARK: - Tools

    private struct ToolResult: Sendable {
        let status: Int32
        let output: String
    }

    /// Runs one of the system's own tools and waits for it. A tool that
    /// cannot be started counts as having failed.
    private nonisolated static func run(_ tool: String, _ arguments: [String]) async -> ToolResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<ToolResult, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { finished in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: ToolResult(
                    status: finished.terminationStatus,
                    output: String(decoding: data, as: UTF8.self)
                ))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: ToolResult(status: -1, output: error.localizedDescription))
            }
        }
    }
}
