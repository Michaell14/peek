import AppKit
import BlinkCore

extension NSScreen {
    /// An identifier that stays the same across restarts and re-plugging,
    /// unlike the numeric display ID.
    var displayKey: String {
        if let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) {
            return string as String
        }
        return localizedName
    }

    /// Height of the strip the menu bar occupies (it includes the camera
    /// housing on notched displays).
    var menuBarHeight: CGFloat {
        let fromVisibleFrame = frame.maxY - visibleFrame.maxY
        return max(fromVisibleFrame, safeAreaInsets.top, 24)
    }

    static var underPointer: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) }
    }

    static func withKey(_ key: String) -> NSScreen? {
        screens.first { $0.displayKey == key }
    }
}

enum Displays {
    @MainActor
    static func target(for setting: DisplayTarget) -> NSScreen? {
        let fallback = NSScreen.underPointer ?? NSScreen.main ?? NSScreen.screens.first
        switch setting.kind {
        case .pointer:
            return fallback
        case .active:
            return NSScreen.main ?? fallback
        case .fixed:
            return setting.displayKey.flatMap(NSScreen.withKey) ?? fallback
        }
    }
}
