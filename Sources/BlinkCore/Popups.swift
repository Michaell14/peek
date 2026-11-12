import Foundation

/// What to do when a page in a web tile asks for a new window.
public enum NewWindowPolicy {
    public enum Choice: Equatable {
        /// Open it as a small window of its own, still linked to the page
        /// that opened it. Sign-in pop-ups ("Sign in with Google") need this:
        /// they report back to that page and then close themselves.
        case popup
        /// Load it in the tile instead. A tile is one page, so a link that
        /// asks for a new tab opens in place.
        case sameTile
        /// Do nothing.
        case ignore
    }

    /// - Parameters:
    ///   - isLinkClick: someone clicked a link that asks for a new window
    ///     (`target="_blank"`), as opposed to the page's script opening one.
    ///   - isInUse: the overlay is open and someone is using it. A page that
    ///     opens windows while it is only being glanced at, or is hidden,
    ///     gets nothing.
    public static func choice(isLinkClick: Bool, isInUse: Bool) -> Choice {
        guard isInUse else { return .ignore }
        return isLinkClick ? .sameTile : .popup
    }
}

/// How big a page's pop-up window is.
public enum PopupSizing {
    public static let defaultSize = (width: 480.0, height: 640.0)
    public static let minimumSize = (width: 360.0, height: 420.0)
    /// Room left around a pop-up on the screen.
    public static let margin = 40.0

    /// The size the page asked for (`window.open(url, name, "width=…,height=…")`),
    /// or a sign-in sized window if it did not say, kept to a usable size that
    /// fits on the screen.
    public static func size(
        requestedWidth: Double?,
        requestedHeight: Double?,
        screenWidth: Double,
        screenHeight: Double
    ) -> (width: Double, height: Double) {
        func fit(_ requested: Double?, fallback: Double, minimum: Double, screen: Double) -> Double {
            let largest = max(minimum, screen - margin * 2)
            guard let requested, requested.isFinite, requested > 0 else { return min(fallback, largest) }
            return min(max(requested, minimum), largest)
        }
        return (
            fit(requestedWidth, fallback: defaultSize.width, minimum: minimumSize.width, screen: screenWidth),
            fit(requestedHeight, fallback: defaultSize.height, minimum: minimumSize.height, screen: screenHeight)
        )
    }
}
