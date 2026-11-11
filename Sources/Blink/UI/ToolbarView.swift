import BlinkCore
import SwiftUI

/// The controls at the right of the overlay's top strip: one glass capsule.
struct ToolbarView: View {
    @ObservedObject var state: OverlayState
    let actions: OverlayActions

    var body: some View {
        HStack(spacing: 4) {
            if state.isPicking {
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
                ModeSwitch(mode: state.mode, onChange: actions.setMode)
                    .help("Flow arranges tiles in columns for you. Freeform lets you place them anywhere.")

                ToolbarIconButton(symbol: "plus", action: actions.add)
                    .help("Add a website, file or widget (⌘N)")

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
        if state.isEditing { return "Drag a tile to move it, or its edge to resize" }
        return "\(state.shortcutText) or esc to close"
    }
}

private struct ToolbarIconButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 24)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Flow or Freeform, with a highlight that slides between the two.
private struct ModeSwitch: View {
    let mode: LayoutMode
    let onChange: (LayoutMode) -> Void

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            segment(.flow, title: "Flow", symbol: "rectangle.split.3x1")
            segment(.freeform, title: "Freeform", symbol: "rectangle.on.rectangle")
        }
        .padding(2)
        .background(Color.white.opacity(0.07), in: Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: mode)
    }

    private func segment(_ value: LayoutMode, title: String, symbol: String) -> some View {
        Button {
            onChange(value)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(mode == value ? Color.primary : Color.secondary)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background {
                if mode == value {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
