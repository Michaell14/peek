import BlinkCore
import SwiftUI

/// The controls at the right of the overlay's top strip: one glass capsule.
struct ToolbarView: View {
    @ObservedObject var state: OverlayState
    let actions: OverlayActions

    var body: some View {
        HStack(spacing: 4) {
            if let name = state.previewName, !state.isShelfOpen, !state.hidesPreviewBar {
                ToolbarIconButton(symbol: "chevron.left") { actions.previewStep(-1) }
                    .help("The template before (←)")
                VStack(spacing: 0) {
                    Text(name)
                        .font(.system(size: 12, weight: .semibold))
                    Text(state.previewPosition)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(minWidth: 96)
                ToolbarIconButton(symbol: "chevron.right") { actions.previewStep(1) }
                    .help("The template after (→)")
                Button("Cancel", action: actions.cancelPreview)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 9)
                    .help("Put the board back as it was (esc)")
                Button("Use Template", action: actions.keepPreview)
                    .buttonStyle(AccentButtonStyle())
                    .help("Keep this board (↩)")
            } else if state.isPicking {
                Text("Click anything on the page to hide it")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
                KeyCap("↑")
                KeyCap("↓")
                Text("widen or narrow")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 4)
                Button("Done", action: actions.stopPicking)
                    .buttonStyle(AccentButtonStyle())
            } else {
                ToolbarIconButton(symbol: "plus", action: actions.add)
                    .help("Add a website, file or widget (⌘N)")

                ToolbarIconButton(symbol: "square.grid.2x2", isOn: state.isShelfOpen, action: actions.templates)
                    .help("Templates: point at one to see it on your board")

                if state.isEditing {
                    Button("Done", action: actions.toggleEditing)
                        .buttonStyle(AccentButtonStyle())
                        .help("Finish arranging (⌘E)")
                } else {
                    Button(action: actions.toggleEditing) {
                        Text("Edit")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 11)
                            .frame(height: 24)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Move, resize and remove tiles (⌘E)")
                }

                ToolbarIconButton(symbol: "gearshape", action: actions.openSettings)
                    .help("Settings (⌘,)")
            }
        }
        .lineLimit(1)
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
        .fixedSize()
    }
}

/// The name and a one-line hint at the left of the top strip.
struct BrandView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        HStack(spacing: 7) {
            BrandMark(size: 13)
            Text("Blink")
                .font(.system(size: 12.5, weight: .semibold))
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var hint: String {
        if state.isShelfOpen { return "Your tiles come back if you do not choose one" }
        if state.previewName != nil { return "Trying a template: your tiles come back if you cancel" }
        if state.isEditing { return "Drag a tile to move or stack it, or an edge to resize it" }
        return "\(state.shortcutText) or esc to close"
    }
}

private struct ToolbarIconButton: View {
    let symbol: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? Color.blinkAccent : Color.primary)
                .frame(width: 26, height: 24)
                .background(isOn ? Color.blinkAccent.opacity(0.16) : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
