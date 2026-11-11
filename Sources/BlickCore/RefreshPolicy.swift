import Foundation

/// Auto-refresh for web tiles.
public enum RefreshPolicy {
    /// The intervals offered in the tile menu, in seconds. Zero is "off".
    public static let presets: [Double] = [0, 30, 60, 300, 900, 1800, 3600]

    public static func label(for interval: Double) -> String {
        guard interval > 0 else { return "Off" }
        if interval < 60 { return "\(Int(interval)) seconds" }
        if interval < 3600 {
            let minutes = Int((interval / 60).rounded())
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        let hours = Int((interval / 3600).rounded())
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    /// A page is refreshed once its interval has elapsed, but never out from
    /// under someone who is using it.
    public static func isDue(lastLoaded: Date, interval: Double, now: Date, isInUse: Bool) -> Bool {
        guard interval > 0, !isInUse else { return false }
        return now.timeIntervalSince(lastLoaded) >= interval
    }
}
