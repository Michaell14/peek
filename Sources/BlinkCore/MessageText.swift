import Foundation

/// Reading what the Messages app keeps on this Mac (its database at
/// ~/Library/Messages/chat.db), in forms the Messages widget can show.
public enum MessageText {
    /// The text of a message saved only as an archived attributed string,
    /// which is how Messages has saved most text since macOS 13.
    ///
    /// The archive is Apple's old "typedstream" format. The text is the
    /// first string after the `NSString` class name: a `+` marks it, then a
    /// length (one byte, or 0x81 and two bytes, or 0x82 and four, little
    /// endian), then that many bytes of UTF-8.
    public static func fromAttributedBody(_ body: [UInt8]) -> String? {
        let marker = Array("NSString".utf8)
        guard body.count > marker.count,
              let start = (0...(body.count - marker.count)).first(where: { body[$0..<($0 + marker.count)].elementsEqual(marker) })
        else { return nil }

        var index = start + marker.count
        guard let plus = body[index..<min(index + 16, body.count)].firstIndex(of: 0x2B) else { return nil }
        index = plus + 1
        guard index < body.count else { return nil }

        let length: Int
        switch body[index] {
        case 0x81:
            guard index + 2 < body.count else { return nil }
            length = Int(body[index + 1]) | Int(body[index + 2]) << 8
            index += 3
        case 0x82:
            guard index + 4 < body.count else { return nil }
            length = Int(body[index + 1]) | Int(body[index + 2]) << 8 | Int(body[index + 3]) << 16 | Int(body[index + 4]) << 24
            index += 5
        case let byte where byte < 0x80:
            length = Int(byte)
            index += 1
        default:
            return nil
        }
        guard length > 0, index + length <= body.count else { return nil }
        return String(decoding: body[index..<(index + length)], as: UTF8.self)
    }

    /// What to show for a message: its text, or the text inside its archive,
    /// without the placeholder characters that stand for attachments.
    public static func display(text: String?, attributedBody: [UInt8]) -> String {
        let raw = (text?.isEmpty == false ? text : nil) ?? fromAttributedBody(attributedBody) ?? ""
        let cleaned = raw.replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Attachment" : cleaned
    }

    /// Messages counts time from the start of 2001: in nanoseconds since
    /// macOS 10.13, in seconds before that.
    public static func date(fromMessagesTime value: Int64) -> Date {
        let seconds = abs(value) > 10_000_000_000 ? Double(value) / 1_000_000_000 : Double(value)
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// The other way, for asking the database about a moment.
    public static func messagesTime(from date: Date) -> Int64 {
        Int64(date.timeIntervalSinceReferenceDate * 1_000_000_000)
    }

    /// "MC" for Maya Chen, "D" for Dad; empty for a number or an address,
    /// which get a picture of a person instead.
    public static func initials(for name: String) -> String {
        guard name.contains(where: \.isLetter), !name.contains("@") else { return "" }
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).filter { $0.first?.isLetter == true }
        return words.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }

    /// When a message came, as briefly as a list row allows: "now", "4m",
    /// "3h" today, "Yesterday", the weekday within a week, then the date.
    public static func shortTime(
        _ date: Date,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3600))h" }
        let today = calendar.startOfDay(for: now)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), date >= yesterday {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: today), date >= weekAgo {
            formatter.setLocalizedDateFormatFromTemplate("EEE")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("dMMM")
        }
        return formatter.string(from: date)
    }

    /// The digits that identify a phone number whichever way it is written,
    /// with or without a country code: its last ten.
    public static func phoneKey(_ handle: String) -> String? {
        let digits = handle.filter(\.isNumber)
        guard digits.count >= 6, !handle.contains("@") else { return nil }
        return String(digits.suffix(10))
    }

    /// A name for a group without one: "Maya, Leo and Sam", or "Maya, Leo
    /// and 3 others".
    public static func groupTitle(_ names: [String]) -> String {
        let firsts = names.map { name in
            name.contains("@") || name.first == "+" || name.first?.isNumber == true
                ? name
                : String(name.split(separator: " ").first ?? Substring(name))
        }
        switch firsts.count {
        case 0: return "Group"
        case 1: return firsts[0]
        case 2: return "\(firsts[0]) and \(firsts[1])"
        case 3: return "\(firsts[0]), \(firsts[1]) and \(firsts[2])"
        default: return "\(firsts[0]), \(firsts[1]) and \(firsts.count - 2) others"
        }
    }
}
