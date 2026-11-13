import BlinkCore
import SwiftUI

/// The Templates button's shelf, along the bottom of the overlay. Pointing at
/// a template puts it on the board above, with the person's own calendar,
/// messages and pages in it; moving away puts the board back. A click keeps it.
///
/// The overlay works out which card is under the pointer itself (see
/// `card(at:width:)`), because a window in a background app is not reliably
/// told when the pointer moves.
struct TemplateShelf: View {
    @ObservedObject var state: OverlayState
    let actions: OverlayActions

    static let maxWidth: CGFloat = 1160
    static let padding: CGFloat = 16
    static let gap: CGFloat = 10
    static let header: CGFloat = 36
    static let cardInset: CGFloat = 6
    static let label: CGFloat = 30
    static let bottomMargin: CGFloat = 14

    private static var count: Int { BoardTemplate.all.count }

    static func width(in available: CGFloat) -> CGFloat {
        min(maxWidth, max(available - 32, 320))
    }

    static func cardWidth(_ width: CGFloat) -> CGFloat {
        (width - 2 * padding - gap * CGFloat(count - 1)) / CGFloat(count)
    }

    static func mapHeight(_ width: CGFloat) -> CGFloat {
        ((cardWidth(width) - 2 * cardInset) * 0.52).rounded()
    }

    static func height(_ width: CGFloat) -> CGFloat {
        padding + header + cardInset + mapHeight(width) + label + padding
    }

    /// The card at a point in the shelf (origin top left), if any.
    static func card(at point: CGPoint, width: CGFloat) -> Int? {
        let top = padding + header
        guard point.y >= top, point.y <= height(width) - padding + 4 else { return nil }
        let x = point.x - padding
        let step = cardWidth(width) + gap
        guard x >= 0 else { return nil }
        let index = Int(x / step)
        guard index < count, x - CGFloat(index) * step <= cardWidth(width) else { return nil }
        return index
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            VStack(alignment: .leading, spacing: 0) {
                header
                    .frame(height: Self.header, alignment: .top)
                HStack(alignment: .top, spacing: Self.gap) {
                    ForEach(BoardTemplate.all) { template in
                        card(template, width: width)
                    }
                }
            }
            .padding(Self.padding)
            .frame(width: width, height: geometry.size.height, alignment: .topLeading)
        }
        .background(
            ZStack {
                // A lighter, raised layer, so it reads as sitting on top of
                // the board rather than sunk into it.
                Color(white: 0.16).opacity(0.96)
                LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.17), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 34, y: 14)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("TEMPLATES")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(state.shelfShowing == nil ? 0.7 : 0.9))
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.15), value: hint)
            Spacer(minLength: 8)
            Button(action: actions.closeShelf) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.07), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close (esc)")
        }
    }

    private var hint: String {
        if let id = state.shelfShowing, let template = BoardTemplate.all.first(where: { $0.id == id }) {
            return "Previewing \(template.name). Click to use it; move away and your board comes back."
        }
        return "Point at one to see it on your board, with your own things in it."
    }

    private func card(_ template: BoardTemplate, width: CGFloat) -> some View {
        let showing = state.shelfShowing == template.id
        let pointed = state.shelfPointed == template.id
        return Button {
            actions.chooseFromShelf(template)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                TemplateMap(template: template)
                    .padding(6)
                    .frame(height: Self.mapHeight(width))
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
                HStack(spacing: 6) {
                    Image(systemName: template.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.blinkAccent)
                    Text(template.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
                .frame(height: Self.label)
            }
            .padding([.top, .horizontal], Self.cardInset)
            .frame(width: Self.cardWidth(width), alignment: .leading)
            .background(
                showing ? Color.blinkAccent.opacity(0.14) : Color.white.opacity(pointed ? 0.11 : 0.06),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(showing ? Color.blinkAccent.opacity(0.6) : Color.white.opacity(pointed ? 0.18 : 0.08), lineWidth: 1)
            )
            .offset(y: pointed ? -4 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: pointed)
            .animation(.easeOut(duration: 0.16), value: showing)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Use \(template.name)")
    }
}

/// "Using My Day", with a way back, after a template is kept.
struct KeptNoticeView: View {
    @ObservedObject var state: OverlayState
    let undo: () -> Void

    var body: some View {
        ZStack {
            if let name = state.keptName {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color(red: 0.24, green: 0.86, blue: 0.52))
                    Text("Using \(name)")
                        .font(.system(size: 12, weight: .semibold))
                    Button(action: undo) {
                        Text("Undo")
                            .font(.system(size: 11.5, weight: .medium))
                            .padding(.horizontal, 9)
                            .frame(height: 20)
                            .background(Color.white.opacity(0.1), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Put the board back as it was")
                }
                .padding(.leading, 11)
                .padding(.trailing, 4)
                .frame(height: 28)
                .background(Color(red: 0.24, green: 0.86, blue: 0.52).opacity(0.14), in: Capsule())
                .overlay(Capsule().strokeBorder(Color(red: 0.24, green: 0.86, blue: 0.52).opacity(0.35), lineWidth: 1))
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.keptName)
        .fixedSize()
        .environment(\.colorScheme, .dark)
    }
}
