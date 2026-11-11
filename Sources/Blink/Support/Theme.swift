import AppKit
import SwiftUI

/// The look shared across the overlay: dark glass and one warm accent.
enum Theme {
    /// Warm amber, the colour of the lit tile in the app icon.
    static let accent = NSColor(srgbRed: 1.0, green: 0.78, blue: 0.38, alpha: 1)
    /// Hairline around tiles and floating controls.
    static let stroke = NSColor(white: 1, alpha: 0.12)
    /// Laid over a tile while it is being arranged.
    static let coverTint = NSColor(white: 0, alpha: 0.46)
    /// Height of the strip along the top that holds the toolbar.
    static let minimumTopInset: CGFloat = 40
}

extension Color {
    static let blinkAccent = Color(nsColor: Theme.accent)
    /// Cool counterpart to the accent, used for night and for websites.
    static let blinkCool = Color(red: 0.56, green: 0.68, blue: 1.0)
}

/// Blink's mark: three tiles, one of them lit.
struct BrandMark: View {
    var size: CGFloat = 14

    var body: some View {
        let gap = size * 0.13
        let radius = size * 0.16
        HStack(spacing: gap) {
            VStack(spacing: gap) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(0.42))
                    .frame(height: size * 0.3)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(0.42))
            }
            .frame(width: size * 0.4)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.blinkAccent)
        }
        .frame(width: size, height: size)
    }
}

enum BrandGlyph {
    /// The mark as a single-colour image for the menu bar.
    static func menuBarImage(size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let inset: CGFloat = 1.5
            let gap = size * 0.11
            let radius = size * 0.13
            let height = size - 2 * inset
            let leftWidth = (size - 2 * inset - gap) * 0.42
            let lowerHeight = (height - gap) * 0.64

            NSColor.black.setFill()
            let lower = NSRect(x: inset, y: inset, width: leftWidth, height: lowerHeight)
            let upper = NSRect(
                x: inset, y: inset + lowerHeight + gap,
                width: leftWidth, height: height - lowerHeight - gap
            )
            let tall = NSRect(
                x: inset + leftWidth + gap, y: inset,
                width: size - 2 * inset - leftWidth - gap, height: height
            )
            for rect in [lower, upper, tall] {
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Blink"
        return image
    }
}

extension NSImage {
    /// A stretchable rounded rectangle, for giving a visual effect view
    /// rounded corners (its blur ignores ordinary layer masks).
    static func roundedMask(radius: CGFloat) -> NSImage? {
        guard radius > 0 else { return nil }
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

// MARK: - Shared SwiftUI pieces

/// Small capitals over a group of rows.
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }
}

/// A compact segmented control whose highlight slides between options.
struct PillPicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    let selection: Value
    let onChange: (Value) -> Void

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button {
                    onChange(option.value)
                } label: {
                    Text(option.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selection == option.value ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background {
                            if selection == option.value {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.06), in: Capsule())
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selection)
        .fixedSize()
    }
}

/// The one filled button style: amber with dark text.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(Color.blinkAccent.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}

/// A key drawn as a key.
struct KeyCap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
    }
}
