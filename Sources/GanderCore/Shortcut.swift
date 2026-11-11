import Foundation

public enum KeyModifier: String, Codable, CaseIterable, Sendable {
    case control
    case option
    case shift
    case command
    case function

    public var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        case .function: return "fn"
        }
    }
}

public enum ModifierSide: String, Codable, Sendable {
    case any
    case left
    case right
}

public struct ModifierKey: Codable, Hashable, Sendable {
    public var modifier: KeyModifier
    public var side: ModifierSide

    public init(_ modifier: KeyModifier, side: ModifierSide = .any) {
        self.modifier = modifier
        // The fn/Globe key exists once per keyboard.
        self.side = modifier == .function ? .any : side
    }
}

/// Which physical modifier keys are down, decoded from the raw flags that
/// macOS attaches to keyboard events.
public struct ModifierState: Hashable, Sendable {
    public struct Sides: Hashable, Sendable {
        public var down: Bool
        public var left: Bool
        public var right: Bool

        public init(down: Bool = false, left: Bool = false, right: Bool = false) {
            self.down = down || left || right
            self.left = left
            self.right = right
        }
    }

    public var control = Sides()
    public var option = Sides()
    public var shift = Sides()
    public var command = Sides()
    public var function = false

    public init() {}

    // Device-independent bits (NSEvent.ModifierFlags / CGEventFlags).
    public static let shiftMask: UInt64 = 0x20000
    public static let controlMask: UInt64 = 0x40000
    public static let optionMask: UInt64 = 0x80000
    public static let commandMask: UInt64 = 0x100000
    public static let functionMask: UInt64 = 0x800000

    // Device-dependent bits (NX_DEVICE*KEYMASK), which tell left from right.
    public static let leftControlMask: UInt64 = 0x1
    public static let leftShiftMask: UInt64 = 0x2
    public static let rightShiftMask: UInt64 = 0x4
    public static let leftCommandMask: UInt64 = 0x8
    public static let rightCommandMask: UInt64 = 0x10
    public static let leftOptionMask: UInt64 = 0x20
    public static let rightOptionMask: UInt64 = 0x40
    public static let rightControlMask: UInt64 = 0x2000

    public init(rawFlags: UInt64) {
        func sides(_ any: UInt64, _ left: UInt64, _ right: UInt64) -> Sides {
            Sides(
                down: rawFlags & any != 0,
                left: rawFlags & left != 0,
                right: rawFlags & right != 0
            )
        }
        control = sides(Self.controlMask, Self.leftControlMask, Self.rightControlMask)
        option = sides(Self.optionMask, Self.leftOptionMask, Self.rightOptionMask)
        shift = sides(Self.shiftMask, Self.leftShiftMask, Self.rightShiftMask)
        command = sides(Self.commandMask, Self.leftCommandMask, Self.rightCommandMask)
        function = rawFlags & Self.functionMask != 0
    }

    public subscript(modifier: KeyModifier) -> Sides {
        switch modifier {
        case .control: return control
        case .option: return option
        case .shift: return shift
        case .command: return command
        case .function: return Sides(down: function)
        }
    }

    public var isEmpty: Bool {
        !control.down && !option.down && !shift.down && !command.down && !function
    }
}

public struct Shortcut: Codable, Hashable, Sendable {
    /// Virtual key code, or nil for a shortcut made of modifier keys alone
    /// (for example "right ⌘" or "fn").
    public var keyCode: UInt16?
    public var modifiers: [ModifierKey]

    public init(keyCode: UInt16?, modifiers: [ModifierKey]) {
        self.keyCode = keyCode
        // One entry per modifier, in a stable order.
        var seen = Set<KeyModifier>()
        self.modifiers = KeyModifier.allCases.compactMap { modifier in
            guard let key = modifiers.first(where: { $0.modifier == modifier }),
                  seen.insert(modifier).inserted else { return nil }
            return key
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keyCode: (try? c.decodeIfPresent(UInt16.self, forKey: .keyCode)) ?? nil,
            modifiers: c.value(.modifiers, default: [])
        )
    }

    /// ⌥` — easy to hold with one hand and rarely claimed by other apps.
    public static let `default` = Shortcut(keyCode: 50, modifiers: [ModifierKey(.option)])

    public var isValid: Bool {
        keyCode != nil || !modifiers.isEmpty
    }

    /// Plain "modifiers + key" shortcuts can use the system hot-key service,
    /// which needs no permission. Anything that looks at left/right keys, the
    /// fn key, or modifiers on their own has to watch raw keyboard events,
    /// and macOS gates that behind Input Monitoring.
    public var requiresEventTap: Bool {
        keyCode == nil || modifiers.contains { $0.side != .any || $0.modifier == .function }
    }

    /// Modifier mask in the format Carbon's RegisterEventHotKey expects.
    public var carbonModifiers: UInt32 {
        modifiers.reduce(0) { mask, key in
            switch key.modifier {
            case .command: return mask | 0x0100
            case .shift: return mask | 0x0200
            case .option: return mask | 0x0800
            case .control: return mask | 0x1000
            case .function: return mask
            }
        }
    }

    /// True when exactly the shortcut's modifiers are held: nothing missing
    /// and nothing extra.
    public func matchesModifiers(_ state: ModifierState) -> Bool {
        for modifier in KeyModifier.allCases {
            let required = modifiers.first { $0.modifier == modifier }
            let actual = state[modifier]
            if modifier == .function {
                // Arrow and function keys report the fn flag on their own, so
                // it only counts when a key shortcut asks for it explicitly.
                if required != nil {
                    if !actual.down { return false }
                } else if keyCode == nil, actual.down {
                    return false
                }
                continue
            }
            switch required?.side {
            case nil:
                if actual.down { return false }
            case .any?:
                if !actual.down { return false }
            case .left?:
                if !actual.left || actual.right { return false }
            case .right?:
                if !actual.right || actual.left { return false }
            }
        }
        return true
    }

    public var displayString: String {
        var parts = modifiers.map { key -> String in
            switch key.side {
            case .any: return key.modifier.symbol
            case .left: return "Left " + key.modifier.symbol
            case .right: return "Right " + key.modifier.symbol
            }
        }
        if let keyCode {
            parts.append(KeyNames.name(for: keyCode))
        }
        guard !parts.isEmpty else { return "None" }
        let compact = !modifiers.contains { $0.side != .any || $0.modifier == .function }
        return parts.joined(separator: compact ? "" : " ")
    }
}

public enum KeyNames {
    /// Names follow the US ANSI layout, as menu shortcuts conventionally do.
    public static func name(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }

    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        10: "§", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋",
        64: "F17", 65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 71: "Clear",
        75: "Keypad /", 76: "⌤", 78: "Keypad -", 79: "F18", 80: "F19", 81: "Keypad =",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4",
        87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7", 90: "F20", 91: "Keypad 8",
        92: "Keypad 9", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12",
        113: "F15", 114: "Help", 115: "↖", 116: "⇞", 117: "⌦", 118: "F4", 119: "↘",
        120: "F2", 121: "⇟", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

/// Turns the raw keyboard event stream into "shortcut went down / came up".
/// Only used for shortcuts the system hot-key service cannot express.
public struct ShortcutTracker: Sendable {
    public enum Input: Hashable, Sendable {
        case flagsChanged(rawFlags: UInt64)
        case keyDown(keyCode: UInt16, rawFlags: UInt64, isRepeat: Bool)
        case keyUp(keyCode: UInt16, rawFlags: UInt64)
    }

    public enum Output: Hashable, Sendable {
        case pressed
        case released
        /// The modifiers turned out to be the start of some other key combo.
        case cancelled
    }

    public let shortcut: Shortcut
    public private(set) var isActive = false

    public init(shortcut: Shortcut) {
        self.shortcut = shortcut
    }

    public mutating func handle(_ input: Input) -> Output? {
        if let keyCode = shortcut.keyCode {
            return handleKeyShortcut(keyCode, input)
        }
        return handleModifierShortcut(input)
    }

    private mutating func handleKeyShortcut(_ target: UInt16, _ input: Input) -> Output? {
        switch input {
        case .keyDown(let keyCode, let rawFlags, let isRepeat):
            guard keyCode == target, !isRepeat, !isActive,
                  shortcut.matchesModifiers(ModifierState(rawFlags: rawFlags)) else { return nil }
            isActive = true
            return .pressed
        case .keyUp(let keyCode, _):
            guard isActive, keyCode == target else { return nil }
            isActive = false
            return .released
        case .flagsChanged(let rawFlags):
            // Letting go of the modifier first also ends the hold.
            guard isActive, !shortcut.matchesModifiers(ModifierState(rawFlags: rawFlags)) else { return nil }
            isActive = false
            return .released
        }
    }

    private mutating func handleModifierShortcut(_ input: Input) -> Output? {
        switch input {
        case .flagsChanged(let rawFlags):
            let matches = shortcut.matchesModifiers(ModifierState(rawFlags: rawFlags))
            if matches, !isActive {
                isActive = true
                return .pressed
            }
            if !matches, isActive {
                isActive = false
                return .released
            }
            return nil
        case .keyDown(_, _, let isRepeat):
            // Right-⌘ then C is a copy, not a peek.
            guard isActive, !isRepeat else { return nil }
            isActive = false
            return .cancelled
        case .keyUp:
            return nil
        }
    }
}
