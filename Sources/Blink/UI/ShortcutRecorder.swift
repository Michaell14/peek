import AppKit
import BlinkCore
import SwiftUI

/// A field that captures the next key combination pressed in it.
struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: Shortcut
    var onRecordingChange: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        ShortcutRecorderView()
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.shortcut = shortcut
        view.onChange = { shortcut = $0 }
        view.onRecordingChange = onRecordingChange
    }
}

final class ShortcutRecorderView: NSView {
    var shortcut = Shortcut.default {
        didSet { refresh() }
    }

    var onChange: ((Shortcut) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    private let label = NSTextField(labelWithString: "")
    /// The largest set of modifiers held during the current press, so that
    /// releasing them one by one still records the whole chord.
    private var heldModifiers: [ModifierKey] = []

    private var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            heldModifiers = []
            refresh()
            onRecordingChange?(isRecording)
        }
    }

    /// F1…F20: the only keys that make sense as a shortcut on their own.
    private static let functionKeys: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        label.alignment = .center
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -12),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 190, height: 26) }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        if isRecording {
            label.stringValue = heldModifiers.isEmpty
                ? "Press a shortcut…"
                : Shortcut(keyCode: nil, modifiers: heldModifiers).displayString
            label.textColor = .secondaryLabelColor
        } else {
            label.stringValue = shortcut.displayString
            label.textColor = .labelColor
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        }
    }

    // MARK: - Recording

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            isRecording = false
        } else {
            window?.makeFirstResponder(self)
            isRecording = true
        }
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        let state = ModifierState(rawFlags: UInt64(event.modifierFlags.rawValue))
        let modifiers = Self.modifierKeys(from: state, sided: false)
        if event.keyCode == 53, modifiers.isEmpty {
            isRecording = false  // Escape cancels.
            return
        }
        guard !modifiers.isEmpty || Self.functionKeys.contains(event.keyCode) else {
            NSSound.beep()
            return
        }
        commit(Shortcut(keyCode: event.keyCode, modifiers: modifiers))
    }

    /// Combinations with ⌘ arrive here rather than through keyDown.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        keyDown(with: event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        let state = ModifierState(rawFlags: UInt64(event.modifierFlags.rawValue))
        if state.isEmpty {
            // Everything was released without a key in between: the modifiers
            // themselves are the shortcut.
            if !heldModifiers.isEmpty {
                commit(Shortcut(keyCode: nil, modifiers: heldModifiers))
            }
            return
        }
        let current = Self.modifierKeys(from: state, sided: true)
        if current.count >= heldModifiers.count {
            heldModifiers = current
            refresh()
        }
    }

    private func commit(_ recorded: Shortcut) {
        shortcut = recorded
        onChange?(recorded)
        isRecording = false
    }

    /// - Parameter sided: record which of the left/right keys was used.
    ///   Shortcuts with a regular key ignore sides (and fn) so that they can
    ///   use the system hot-key service, which needs no permission.
    private static func modifierKeys(from state: ModifierState, sided: Bool) -> [ModifierKey] {
        var keys: [ModifierKey] = []
        for modifier in [KeyModifier.control, .option, .shift, .command] {
            let sides = state[modifier]
            guard sides.down else { continue }
            var side = ModifierSide.any
            if sided, sides.left != sides.right {
                side = sides.left ? .left : .right
            }
            keys.append(ModifierKey(modifier, side: side))
        }
        if sided, state.function {
            keys.append(ModifierKey(.function))
        }
        return keys
    }
}
