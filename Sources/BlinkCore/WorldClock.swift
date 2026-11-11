import Foundation

/// The text shown for each row of the clock widget.
public enum WorldClock {
    public struct Row: Hashable, Identifiable, Sendable {
        public var id: String
        public var city: String
        public var detail: String
        public var time: String
        public var period: String
        /// Roughly whether the sun is up there (06:00 to 18:00).
        public var isDaytime: Bool
    }

    public static func timeZone(for identifier: String, local: TimeZone) -> TimeZone? {
        identifier == ClockConfig.localZone ? local : TimeZone(identifier: identifier)
    }

    /// "America/New_York" -> "New York".
    public static func cityName(for identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// "Today, +3 hrs", "Tomorrow, +9:30 hrs", "Yesterday, −8 hrs".
    public static func offsetDescription(for zone: TimeZone, relativeTo local: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)

        var here = Calendar(identifier: .gregorian)
        here.timeZone = local
        var there = Calendar(identifier: .gregorian)
        there.timeZone = zone
        let hereDay = here.dateComponents([.year, .month, .day], from: date)
        let thereDay = there.dateComponents([.year, .month, .day], from: date)

        var day = "Today"
        if let a = dayNumber(hereDay), let b = dayNumber(thereDay) {
            if b > a { day = "Tomorrow" }
            if b < a { day = "Yesterday" }
        }
        guard seconds != 0 else { return day }

        let minutes = abs(seconds) / 60
        let sign = seconds > 0 ? "+" : "−"
        let amount = minutes % 60 == 0
            ? "\(minutes / 60)"
            : "\(minutes / 60):" + String(format: "%02d", minutes % 60)
        let unit = minutes == 60 ? "hr" : "hrs"
        return "\(day), \(sign)\(amount) \(unit)"
    }

    public static func row(
        identifier: String,
        at date: Date,
        local: TimeZone,
        uses24Hour: Bool
    ) -> Row? {
        guard let zone = timeZone(for: identifier, local: local) else { return nil }
        let isLocal = identifier == ClockConfig.localZone

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = uses24Hour ? "HH:mm" : "h:mm"
        let time = formatter.string(from: date)
        formatter.dateFormat = "a"
        let period = uses24Hour ? "" : formatter.string(from: date)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: date)

        return Row(
            id: identifier,
            city: isLocal ? "Local" : cityName(for: zone.identifier),
            detail: isLocal
                ? cityName(for: zone.identifier)
                : offsetDescription(for: zone, relativeTo: local, at: date),
            time: time,
            period: period,
            isDaytime: hour >= 6 && hour < 18
        )
    }

    private static func dayNumber(_ components: DateComponents) -> Int? {
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        return year * 10_000 + month * 100 + day
    }
}
