import Foundation

/// A version such as 0.2.0, compared number by number.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    /// The numbers, without trailing zeros, so that 1.2 and 1.2.0 are equal.
    public let parts: [Int]

    /// Reads "0.2.0", "v0.2" or "1.4.1-beta" (anything after the numbers is
    /// ignored). Returns nil for text that does not start with a number.
    public init?(_ text: String) {
        var rest = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if rest.first == "v" || rest.first == "V" { rest = rest.dropFirst() }
        let numeric = rest.prefix { ("0"..."9").contains($0) || $0 == "." }
        let pieces = numeric.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty, pieces.count <= 4 else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard piece.count <= 9, let number = Int(piece) else { return nil }
            parts.append(number)
        }
        while parts.count > 1, parts.last == 0 { parts.removeLast() }
        self.parts = parts
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public var description: String {
        (parts.count == 1 ? parts + [0] : parts).map(String.init).joined(separator: ".")
    }
}

/// A release as GitHub's API describes it. Only the fields Blink reads.
public struct ReleaseInfo: Decodable, Equatable, Sendable {
    public struct Asset: Decodable, Equatable, Sendable {
        public let name: String
        public let url: URL
        public let size: Int

        public init(name: String, url: URL, size: Int = 0) {
            self.name = name
            self.url = url
            self.size = size
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case url = "browser_download_url"
            case size
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            url = try c.decode(URL.self, forKey: .url)
            size = (try? c.decodeIfPresent(Int.self, forKey: .size)) ?? 0
        }
    }

    public let tag: String
    public let notes: String
    public let page: URL?
    public let isDraft: Bool
    public let isPrerelease: Bool
    public let assets: [Asset]

    public init(tag: String, notes: String = "", page: URL? = nil, isDraft: Bool = false, isPrerelease: Bool = false, assets: [Asset] = []) {
        self.tag = tag
        self.notes = notes
        self.page = page
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
        self.assets = assets
    }

    private enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case notes = "body"
        case page = "html_url"
        case isDraft = "draft"
        case isPrerelease = "prerelease"
        case assets
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tag = try c.decode(String.self, forKey: .tag)
        notes = ((try? c.decodeIfPresent(String.self, forKey: .notes)) ?? nil) ?? ""
        page = (try? c.decodeIfPresent(URL.self, forKey: .page)) ?? nil
        isDraft = ((try? c.decodeIfPresent(Bool.self, forKey: .isDraft)) ?? nil) ?? false
        isPrerelease = ((try? c.decodeIfPresent(Bool.self, forKey: .isPrerelease)) ?? nil) ?? false
        // One odd asset should not hide the release.
        var list: [Asset] = []
        if var items = try? c.nestedUnkeyedContainer(forKey: .assets) {
            while !items.isAtEnd {
                if let asset = try? items.decode(Asset.self) {
                    list.append(asset)
                } else {
                    _ = try? items.decode(Skipped.self)
                }
            }
        }
        assets = list
    }

    private struct Skipped: Decodable {}
}

/// A newer version someone could move to.
public struct UpdateOffer: Equatable, Sendable {
    public let version: AppVersion
    /// The version as its release spells it, for showing to people.
    public let versionText: String
    public let notes: String
    /// The release's page on GitHub.
    public let page: URL?
    /// The archive Blink can install by itself, when the release has one and
    /// it comes from somewhere Blink is willing to fetch code from.
    public let archive: URL?
    public let archiveSize: Int
}

/// Where updates come from.
public struct UpdateSource: Equatable, Sendable {
    /// "owner/name" on GitHub.
    public let repository: String
    /// The address that answers with the newest release.
    public let feed: URL
    /// False when the feed was given on the command line, as the checks do.
    public let isOfficial: Bool

    public init(repository: String, feed: URL? = nil) {
        self.repository = repository
        let official = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
        self.feed = feed ?? official ?? URL(fileURLWithPath: "/")
        isOfficial = feed == nil
    }

    /// The disk image people download by hand.
    public var downloadPage: URL? {
        URL(string: "https://github.com/\(repository)/releases/latest")
    }

    /// Blink only fetches code over HTTPS from its own releases on GitHub. A
    /// feed named on the command line may also serve its own archive.
    public func trusts(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return false }
        if scheme == "https", host == "github.com", url.path.hasPrefix("/\(repository)/releases/download/") {
            return true
        }
        guard !isOfficial else { return false }
        return scheme == feed.scheme?.lowercased() && host == feed.host?.lowercased() && url.port == feed.port
    }
}

public enum UpdateCheck {
    /// The asset an installed Blink updates itself from.
    public static let archiveName = "Blink.zip"
    /// How often Blink asks, in seconds.
    public static let interval: TimeInterval = 24 * 60 * 60

    /// What, if anything, to offer someone running `current`.
    public static func offer(from release: ReleaseInfo, current: AppVersion, source: UpdateSource) -> UpdateOffer? {
        guard !release.isDraft, !release.isPrerelease,
              let version = AppVersion(release.tag), version > current else { return nil }
        let archive = release.assets.first { $0.name == archiveName && source.trusts($0.url) }
        var text = release.tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        return UpdateOffer(
            version: version,
            versionText: text,
            notes: release.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            page: release.page,
            archive: archive?.url,
            archiveSize: archive?.size ?? 0
        )
    }

    /// True when it is time to ask again. A clock that has gone backwards
    /// counts as due, rather than putting the next check off indefinitely.
    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed >= interval || elapsed < 0
    }

    public enum Problem: Error, Equatable, Sendable {
        /// The archive holds some other app.
        case differentApp(found: String)
        /// The archive holds a different version from the one offered.
        case differentVersion(found: String)
    }

    /// Checks that what was unpacked is the app and version that was offered.
    public static func problem(
        withIdentifier identifier: String?,
        version: String?,
        expecting offer: UpdateOffer,
        identifier ours: String
    ) -> Problem? {
        guard let identifier, identifier == ours else {
            return .differentApp(found: identifier ?? "nothing")
        }
        guard let version, let found = AppVersion(version), found == offer.version else {
            return .differentVersion(found: version ?? "nothing")
        }
        return nil
    }
}
