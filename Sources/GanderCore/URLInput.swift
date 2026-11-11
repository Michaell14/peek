import Foundation

/// Turns whatever was typed into the address field into something loadable.
public enum URLInput {
    public static let defaultSearchTemplate = "https://duckduckgo.com/?q=%s"

    public static func resolve(_ text: String, searchTemplate: String = defaultSearchTemplate) -> URL? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        let lowered = input.lowercased()
        for scheme in ["http://", "https://", "file://"] where lowered.hasPrefix(scheme) {
            return URL(string: input) ?? encoded(input)
        }
        if input.hasPrefix("/") || input.hasPrefix("~/") {
            return URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
        }

        if looksLikeHost(input) {
            let scheme = isLocal(host(of: input)) ? "http" : "https"
            if let url = URL(string: "\(scheme)://\(input)") ?? encoded("\(scheme)://\(input)") {
                return url
            }
        }
        return search(input, template: searchTemplate)
    }

    public static func search(_ query: String, template: String = defaultSearchTemplate) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let escaped = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: template.replacingOccurrences(of: "%s", with: escaped))
    }

    /// A short label for a page: the host without a leading "www.".
    public static func displayHost(for url: URL) -> String {
        if url.isFileURL { return url.lastPathComponent }
        guard let host = url.host, !host.isEmpty else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: - Private

    private static func encoded(_ string: String) -> URL? {
        string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:))
    }

    private static func host(of input: String) -> String {
        var rest = Substring(input)
        if let slash = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            rest = rest[..<slash]
        }
        if let at = rest.lastIndex(of: "@") {
            rest = rest[rest.index(after: at)...]
        }
        if rest.hasPrefix("[") {
            return String(rest)  // IPv6 literal
        }
        if let colon = rest.lastIndex(of: ":") {
            rest = rest[..<colon]
        }
        return String(rest).lowercased()
    }

    private static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".localhost") { return true }
        return isIPv4(host)
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 3 && part.allSatisfy(\.isASCIIDigit) && Int(part)! <= 255
        }
    }

    private static func looksLikeHost(_ input: String) -> Bool {
        guard !input.contains(where: \.isWhitespace) else { return false }
        let host = host(of: input)
        guard !host.isEmpty else { return false }
        if host == "localhost" || isIPv4(host) || host.hasPrefix("[") { return true }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let last = labels.last else { return false }
        let validLabels = labels.allSatisfy { label in
            !label.isEmpty && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
        // "example.com" is a site; "3.14" and "what.is this" are searches.
        return validLabels && last.count >= 2 && last.allSatisfy(\.isLetter)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
