import AppKit
import BlinkCore
import EventKit
import SwiftUI

// The tour's look: Blink's dark glass, a cool blue for what to press, the
// amber of the lit tile, and one type scale used throughout.
private enum Tour {
    static let ink = Color(red: 0.95, green: 0.953, blue: 0.96)
    static let ink2 = Color(red: 0.886, green: 0.902, blue: 0.933).opacity(0.74)
    static let ink3 = Color(red: 0.886, green: 0.902, blue: 0.933).opacity(0.56)
    static let hairline = Color.white.opacity(0.07)
    static let cool = Color(red: 0.616, green: 0.729, blue: 1.0)
    static let onCool = Color(red: 0.04, green: 0.07, blue: 0.15)
    static let lit = Color(red: 1.0, green: 0.78, blue: 0.38)
    static let green = Color(red: 0.24, green: 0.86, blue: 0.52)
    static let warning = Color(red: 1.0, green: 0.6, blue: 0.57)

    static let arrive = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let settle = Animation.spring(response: 0.34, dampingFraction: 0.9)

    // Type scale.
    static let display = Font.system(size: 44, weight: .bold)
    static let title = Font.system(size: 22, weight: .semibold)
    static let coachTitle = Font.system(size: 19, weight: .semibold)
    static let lead = Font.system(size: 16, weight: .medium)
    static let body = Font.system(size: 13.5)
    static let small = Font.system(size: 12.5)
    static let caption = Font.system(size: 10, weight: .semibold)
}

/// The height each step's content wants, measured as laid out. Keyed by
/// step, so a step on its way out does not count.
private struct ContentHeights: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { max($0, $1) }
    }
}

struct OnboardingView: View {
    @ObservedObject var tour: OnboardingModel
    @ObservedObject var model: AppModel
    @ObservedObject var hotkeys: HotkeyMonitor

    /// Each step's width. Its height is whatever its content needs.
    static func width(for step: OnboardingModel.Step) -> CGFloat {
        switch step {
        case .hello: return 500
        case .hold, .tap: return 600
        case .shortcut: return 620
        case .board: return 800
        case .access: return 620
        case .ready: return 680
        }
    }

    /// A first guess at the height, used until the content has been measured.
    static func estimatedHeight(for step: OnboardingModel.Step) -> CGFloat {
        switch step {
        case .hello: return 470
        case .hold: return 232
        case .tap: return 276
        case .shortcut: return 540
        case .board: return 76
        case .access: return 470
        case .ready: return 420
        }
    }

    var body: some View {
        let step = tour.step
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color.white.opacity(0.085), Color.white.opacity(0.045)], startPoint: .top, endPoint: .bottom)
            Color(red: 0.055, green: 0.06, blue: 0.07).opacity(0.62)
            content
                .frame(width: Self.width(for: tour.step))
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeights.self, value: [step.rawValue: proxy.size.height])
                })
                .id(tour.step)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)).animation(Tour.arrive.delay(0.08)),
                    removal: .opacity.animation(.easeOut(duration: 0.1))
                ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .foregroundStyle(Tour.ink)
        .environment(\.colorScheme, .dark)
        .onPreferenceChange(ContentHeights.self) { heights in
            onMainActor {
                let rounded = heights.mapValues { $0.rounded(.up) }
                if tour.contentHeights != rounded { tour.contentHeights = rounded }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tour.step {
        case .hello: HelloStep(tour: tour)
        case .hold: HoldStep(tour: tour, hotkeys: hotkeys)
        case .tap: TapStep(tour: tour)
        case .shortcut: ShortcutStep(tour: tour, model: model, hotkeys: hotkeys)
        case .board: BoardStep(tour: tour)
        case .access: AccessStep(tour: tour)
        case .ready: ReadyStep(tour: tour)
        }
    }
}

// MARK: - Pieces

/// The one filled button: cool blue, dark text, an arrow that leans forward
/// on hover.
private struct TourButton: View {
    let title: String
    var arrow = true
    var height: CGFloat = 36
    var minWidth: CGFloat = 0
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                if arrow {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11.5, weight: .bold))
                        .offset(x: isHovering ? 2.5 : 0)
                }
            }
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(Tour.onCool)
            .padding(.horizontal, 18)
            .frame(minWidth: minWidth)
            .frame(height: height)
            .background(
                Capsule()
                    .fill(Tour.cool.opacity(isHovering ? 1 : 0.92))
                    .shadow(color: Tour.cool.opacity(isHovering ? 0.35 : 0), radius: 12, y: 4)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.16)) { isHovering = hovering } }
        .keyboardShortcut(.defaultAction)
    }
}

private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct TourLink: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isHovering ? Tour.ink : Tour.ink3)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering } }
    }
}

/// "STEP 2 OF 4", four segments (this step's fills in as it opens), and Skip.
private struct StepHeader: View {
    let number: Int
    var skip: (() -> Void)?

    @State private var filled = false

    var body: some View {
        HStack(spacing: 12) {
            Text("STEP \(number) OF 4")
                .font(Tour.caption)
                .tracking(0.9)
                .foregroundStyle(Tour.ink3)
                .fixedSize()
            HStack(spacing: 4) {
                ForEach(1...4, id: \.self) { segment in
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule()
                                .fill(Tour.cool)
                                .frame(width: proxy.size.width * fill(segment))
                        }
                    }
                    .frame(height: 3)
                }
            }
            if let skip {
                TourLink(title: "Skip", action: skip)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(0.25)) { filled = true }
        }
    }

    private func fill(_ segment: Int) -> CGFloat {
        if segment < number { return 1 }
        if segment == number { return filled ? 1 : 0 }
        return 0
    }
}

/// A tick that pops in with a ring going out from it.
private struct Tick: View {
    @State private var shown = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Tour.green.opacity(0.6), lineWidth: 1.5)
                .scaleEffect(shown ? 1.9 : 0.8)
                .opacity(shown ? 0 : 0.9)
                .animation(.easeOut(duration: 0.7), value: shown)
            Image(systemName: "checkmark")
                .font(.system(size: 10.5, weight: .heavy))
                .foregroundStyle(Tour.green)
                .frame(width: 22, height: 22)
                .background(Tour.green.opacity(0.18), in: Circle())
                .scaleEffect(shown ? 1 : 0.4)
                .opacity(shown ? 1 : 0)
                .animation(.spring(response: 0.32, dampingFraction: 0.55), value: shown)
        }
        .frame(width: 22, height: 22)
        .onAppear { shown = true }
    }
}

/// A key drawn large, the way it looks on the keyboard.
private struct BigCap: View {
    let key: OnboardingKey
    var size: CGFloat = 74
    var pressed = false
    /// A light dip, without the glow of a real press.
    var nudged = false
    var lit = false

    /// What a key prints above its own character, for the keys people
    /// tend to choose.
    static let shifted: [String: String] = [
        "`": "~", "1": "!", "2": "@", "3": "#", "-": "_", "=": "+", "[": "{", "]": "}",
        ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?", "\\": "|",
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.17, green: 0.177, blue: 0.2), Color(red: 0.13, green: 0.137, blue: 0.157)],
                    startPoint: .top, endPoint: .bottom
                ))
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .strokeBorder(pressed ? Tour.cool.opacity(0.65) : Color.white.opacity(0.2), lineWidth: 1)
            if let name = key.name {
                Text(key.symbol)
                    .font(.system(size: size * 0.24))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, size * 0.11)
                    .padding(.trailing, size * 0.15)
                Text(name)
                    .font(.system(size: size * 0.15, weight: .medium, design: .monospaced))
                    .foregroundStyle(Tour.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, size * 0.13)
                    .padding(.bottom, size * 0.12)
                    .padding(.trailing, 4)
                Circle()
                    .fill(lit ? Tour.lit : Color.white.opacity(0.18))
                    .shadow(color: lit ? Tour.lit.opacity(0.8) : .clear, radius: 4)
                    .frame(width: size * 0.08, height: size * 0.08)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, size * 0.14)
                    .padding(.top, size * 0.15)
            } else if let shifted = Self.shifted[key.symbol] {
                VStack(spacing: size * 0.02) {
                    Text(shifted)
                        .font(.system(size: size * 0.2))
                        .foregroundStyle(Tour.ink2)
                    Text(key.symbol)
                        .font(.system(size: size * 0.36, weight: .semibold))
                }
                .offset(y: size * 0.03)
            } else {
                Text(key.symbol)
                    .font(.system(size: key.symbol.count > 2 ? size * 0.2 : size * 0.35, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 6)
            }
        }
        .frame(minWidth: size, idealWidth: key.symbol.count > 3 ? size * 1.5 : size, maxWidth: key.symbol.count > 3 ? size * 1.8 : size)
        .frame(height: size)
        .fixedSize(horizontal: true, vertical: false)
        // A hard edge underneath for the key's side, a soft one for its shadow.
        .background(
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(Color(red: 0.047, green: 0.055, blue: 0.07))
                .offset(y: pressed ? 1 : (nudged ? 2.5 : 4))
        )
        .shadow(color: pressed ? Tour.cool.opacity(0.32) : Color.black.opacity(0.45), radius: pressed ? 14 : 12, y: pressed ? 0 : (nudged ? 7 : 10))
        .offset(y: pressed ? 2 : (nudged ? 1.5 : 0))
        .animation(.easeOut(duration: 0.08), value: pressed)
        .animation(.easeInOut(duration: 0.14), value: nudged)
        .animation(.easeOut(duration: 0.12), value: lit)
    }
}

/// How many times the keys have dipped, for the self-check.
@MainActor
enum OnboardingKeyNudges {
    static var count = 0
}

/// The shortcut's keys, large. While waiting to be pressed they dip once
/// every couple of seconds, as an invitation, and light up only when the
/// real keys are down.
private struct CapsRow: View {
    let caps: [OnboardingKey]
    var pressed = false
    var inviting = false
    var size: CGFloat = 74

    @State private var nudged = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, key in
                BigCap(key: key, size: size, pressed: pressed, nudged: nudged && !pressed, lit: pressed && key.name != nil)
            }
        }
        // A plain timer rather than a phase animation: its pauses change
        // nothing on screen, and a phase animation skips straight past them.
        .task(id: inviting && !pressed) {
            nudged = false
            guard inviting, !pressed else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2400))
                guard !Task.isCancelled else { break }
                nudged = true
                OnboardingKeyNudges.count += 1
                try? await Task.sleep(for: .milliseconds(180))
                nudged = false
            }
        }
    }
}

/// A key drawn small, in a line of text or the cheat sheet.
private struct SmallCap: View {
    let label: String
    var height: CGFloat = 22

    var body: some View {
        Text(label)
            .font(.system(size: height * 0.5, weight: .medium, design: .monospaced))
            .padding(.horizontal, height * 0.26)
            .frame(minWidth: height, minHeight: height)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.17, green: 0.177, blue: 0.2), Color(red: 0.13, green: 0.137, blue: 0.157)],
                    startPoint: .top, endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: height * 0.26, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: height * 0.26, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            .background(
                RoundedRectangle(cornerRadius: height * 0.26, style: .continuous)
                    .fill(Color(red: 0.047, green: 0.055, blue: 0.07))
                    .offset(y: 1.5)
            )
    }
}

/// Blink's mark, built up tile by tile, the lit one glowing and breathing.
private struct AnimatedMark: View {
    var size: CGFloat = 72
    @State private var shown = false

    var body: some View {
        let gap = size * 0.09
        let radius = size * 0.11
        HStack(spacing: gap) {
            VStack(spacing: gap) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(0.42))
                    .frame(height: size * 0.28)
                    .offset(x: shown ? 0 : -size * 0.2)
                    .opacity(shown ? 1 : 0)
                    .animation(Tour.arrive.delay(0.12), value: shown)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(0.42))
                    .offset(x: shown ? 0 : -size * 0.2)
                    .opacity(shown ? 1 : 0)
                    .animation(Tour.arrive.delay(0.2), value: shown)
            }
            .frame(width: size * 0.37)
            RoundedRectangle(cornerRadius: radius * 1.1, style: .continuous)
                .fill(LinearGradient(colors: [Tour.lit, Tour.lit.opacity(0.88)], startPoint: .top, endPoint: .bottom))
                .phaseAnimator([false, true]) { tile, glowing in
                    tile.shadow(color: Tour.lit.opacity(glowing ? 0.5 : 0.24), radius: glowing ? size * 0.38 : size * 0.22)
                } animation: { _ in .easeInOut(duration: 2.2) }
                .scaleEffect(shown ? 1 : 0.5, anchor: .bottom)
                .opacity(shown ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.34), value: shown)
        }
        .frame(width: size, height: size)
        .onAppear { shown = true }
    }
}

/// Appears a moment after the view does, rising a little.
private struct Arrive: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 7)
            .onAppear { withAnimation(Tour.arrive.delay(delay)) { shown = true } }
    }
}

private extension View {
    func arrive(after delay: Double) -> some View { modifier(Arrive(delay: delay)) }
}

/// A heading and a line under it that cross-fade as they change.
private struct ChangingWords: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topLeading) {
                Text(title)
                    .font(Tour.coachTitle)
                    .tracking(-0.3)
                    .id(title)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 5)),
                        removal: .opacity.combined(with: .offset(y: -5))
                    ))
            }
            ZStack(alignment: .topLeading) {
                Text(detail)
                    .font(Tour.body)
                    .lineSpacing(2.5)
                    .foregroundStyle(Tour.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(detail)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Tour.settle, value: title)
        .animation(.easeOut(duration: 0.2), value: detail)
    }
}

/// "Hold ⌥ ` on your keyboard", with the keys drawn as keys.
private struct KeysHint: View {
    let before: String
    let caps: [OnboardingKey]
    let after: String

    var body: some View {
        HStack(spacing: 6) {
            Text(before)
            HStack(spacing: 3) {
                ForEach(Array(caps.enumerated()), id: \.offset) { _, key in
                    SmallCap(label: key.symbol, height: 19)
                }
            }
            Text(after)
        }
        .font(Tour.small)
        .foregroundStyle(Tour.ink3)
    }
}

private func capsPhrase(_ caps: [OnboardingKey]) -> String {
    caps.map(\.symbol).joined(separator: " and ")
}

// MARK: - 1 · Hello

private struct HelloStep: View {
    @ObservedObject var tour: OnboardingModel

    private let ahead: [(symbol: String, label: String)] = [
        ("eye", "Hold to peek"),
        ("pin", "Tap to stay"),
        ("keyboard", "Pick your key"),
        ("square.grid.2x2", "Try a board"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            AnimatedMark()
                .padding(.top, 46)
            Text("Blink")
                .font(Tour.display)
                .tracking(-1.4)
                .padding(.top, 22)
                .arrive(after: 0.45)
            Text("Everything you check all day,\none key away.")
                .font(Tour.lead)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(Tour.ink.opacity(0.9))
                .padding(.top, 10)
                .arrive(after: 0.55)
            Text("Hold it to look. Let go to get back to work.")
                .font(Tour.body)
                .foregroundStyle(Tour.ink3)
                .padding(.top, 8)
                .arrive(after: 0.62)

            HStack(spacing: 10) {
                ForEach(Array(ahead.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Tour.cool)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
                        Text(item.label)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Tour.ink2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .arrive(after: 0.75 + Double(index) * 0.07)
                }
            }
            .padding(.top, 30)

            TourButton(title: "Get Started", height: 40, minWidth: 200) { tour.advance() }
                .padding(.top, 32)
                .arrive(after: 1.05)
            TourLink(title: "Skip the tour") { tour.skipTour() }
                .padding(.top, 10)
                .arrive(after: 1.12)
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 24)
    }
}

// MARK: - 2 · Hold to peek

private struct HoldStep: View {
    @ObservedObject var tour: OnboardingModel
    @ObservedObject var hotkeys: HotkeyMonitor

    var body: some View {
        let words = self.words
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(number: 1) { tour.advance() }
            HStack(alignment: .center, spacing: 22) {
                CapsRow(caps: tour.caps, pressed: tour.isPeeking, inviting: tour.peeks == 0 && !tour.tappedInstead)
                ChangingWords(title: words.0, detail: words.1)
            }
            .padding(.top, 20)
            Rectangle()
                .fill(Tour.hairline)
                .frame(height: 1)
                .padding(.top, 20)
            footer
                .frame(height: 36)
                .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var words: (String, String) {
        if tour.isPeeking {
            return ("There it is", "Everything you check, over your work. Now let go.")
        }
        if tour.tappedInstead {
            return ("That was a tap", "A quick tap keeps Blink open; that is the next step. Press esc, then hold the keys a little longer.")
        }
        if tour.peeks > 0 {
            return ("And you are back", "Right where you were. That is a peek: no switching apps, no finding your place again.")
        }
        return (
            "Hold \(capsPhrase(tour.caps)) together",
            "Blink comes up over whatever you are doing, for as long as the keys are down."
        )
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            if hotkeys.status == .needsInputMonitoring {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tour.warning)
                Text("macOS has to let Blink see \(tour.shortcutText) first.")
                    .font(Tour.small)
                    .foregroundStyle(Tour.ink2)
                Spacer()
                TourLink(title: "Allow…") { hotkeys.requestInputMonitoring() }
            } else if hotkeys.status == .unavailable {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tour.warning)
                Text("Another app already uses \(tour.shortcutText). Choose a different key in step 3.")
                    .font(Tour.small)
                    .foregroundStyle(Tour.ink2)
                Spacer()
                TourButton(title: "Continue") { tour.advance() }
            } else if tour.isPeeking {
                Label("Let go to get back", systemImage: "hand.raised")
                    .font(Tour.small)
                    .foregroundStyle(Tour.cool)
                    .transition(.opacity)
                Spacer()
            } else if tour.peeks > 0 {
                Tick()
                Text(tour.peeks == 1 ? "One peek. Try it again, or carry on." : "\(tour.peeks) peeks. You have the hang of it.")
                    .font(.system(size: 13))
                    .foregroundStyle(Tour.ink.opacity(0.85))
                    .contentTransition(.numericText())
                Spacer()
                TourButton(title: "Continue") { tour.advance() }
                    .transition(.opacity.combined(with: .offset(x: 8)))
            } else {
                KeysHint(before: "Hold", caps: tour.caps, after: "on your keyboard")
                    .transition(.opacity)
                Spacer()
            }
        }
        .animation(Tour.settle, value: tour.isPeeking)
        .animation(Tour.settle, value: tour.peeks)
    }
}

// MARK: - 3 · Tap to keep it open

private struct TapStep: View {
    @ObservedObject var tour: OnboardingModel

    var body: some View {
        let words = self.words
        let done = tour.openedPinned && tour.closedAfterPin && !tour.isPinned
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(number: 2) { tour.advance() }
            HStack(alignment: .center, spacing: 22) {
                CapsRow(caps: tour.caps, pressed: tour.isPeeking || tour.isPinned, inviting: !tour.openedPinned)
                ChangingWords(title: words.0, detail: words.1)
            }
            .padding(.top, 20)

            HStack(spacing: 8) {
                task("Tap to keep it open", done: tour.openedPinned)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Tour.ink3)
                task("Tap again or esc to close", done: tour.closedAfterPin)
            }
            .padding(.top, 18)

            Rectangle()
                .fill(Tour.hairline)
                .frame(height: 1)
                .padding(.top, 18)
            HStack(spacing: 10) {
                if done {
                    Tick()
                    Text("Both ways, done.")
                        .font(.system(size: 13))
                        .foregroundStyle(Tour.ink.opacity(0.85))
                    Spacer()
                    TourButton(title: "Continue") { tour.advance() }
                        .transition(.opacity.combined(with: .offset(x: 8)))
                } else if tour.isPinned {
                    KeysHint(before: "Tap", caps: tour.caps, after: "again, or press esc")
                        .transition(.opacity)
                    Spacer()
                } else {
                    KeysHint(before: "Press", caps: tour.caps, after: "and let go straight away")
                        .transition(.opacity)
                    Spacer()
                }
            }
            .frame(height: 36)
            .padding(.top, 12)
            .animation(Tour.settle, value: done)
            .animation(Tour.settle, value: tour.isPinned)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var words: (String, String) {
        if tour.isPinned {
            return ("It stays open", "Click, scroll and type in any tile. The bar along the top has Add, Templates, Edit and Settings.")
        }
        if tour.openedPinned, tour.closedAfterPin {
            return ("Peek, or stay a while", "Hold when you only need a look; tap when you want to stay.")
        }
        return ("Now tap instead", "A quick tap keeps Blink open, so you can click, scroll and type in it.")
    }

    private func task(_ label: String, done: Bool) -> some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .strokeBorder(done ? Tour.green : Tour.ink.opacity(0.35), lineWidth: 1.5)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7.5, weight: .heavy))
                        .foregroundStyle(Tour.green)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .frame(width: 15, height: 15)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(done ? Tour.ink : Tour.ink2)
        }
        .padding(.leading, 9)
        .padding(.trailing, 11)
        .frame(height: 28)
        .background(done ? Tour.green.opacity(0.12) : Color.white.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(done ? Tour.green.opacity(0.25) : Color.clear, lineWidth: 1))
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: done)
    }
}

// MARK: - 4 · Your shortcut

private struct ShortcutStep: View {
    @ObservedObject var tour: OnboardingModel
    @ObservedObject var model: AppModel
    @ObservedObject var hotkeys: HotkeyMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(number: 3) { tour.advance() }
            Text("The key that opens Blink")
                .font(Tour.title)
                .tracking(-0.4)
                .padding(.top, 22)
            Text("Pick one your fingers find without looking. You can change it any time in Settings.")
                .font(Tour.body)
                .lineSpacing(2.5)
                .foregroundStyle(Tour.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            // The shortcut, drawn as the keys themselves.
            ZStack {
                CapsRow(caps: tour.caps, size: 62)
                    .id(model.settings.shortcut)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85).combined(with: .opacity).combined(with: .offset(y: -8)),
                        removal: .opacity
                    ))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 104)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.05)))
            .animation(.spring(response: 0.36, dampingFraction: 0.72), value: model.settings.shortcut)
            .padding(.top, 18)

            VStack(spacing: 8) {
                option(.standard, "Option and the key above Tab", "Works straight away. Nothing to allow.",
                       badge: "Recommended", keys: Shortcut.default.displayString)
                option(.function, "fn on its own", "One key, easy to reach. macOS asks you to allow Input Monitoring first.",
                       keys: "fn")
                option(.custom, "Something else", "Any combination, or one modifier on its own, such as the right ⌘.",
                       keys: tour.shortcutChoice == .custom ? tour.shortcutText : "Record…")
            }
            .padding(.top, 14)

            if tour.shortcutChoice == .custom {
                HStack(spacing: 12) {
                    Text("Your shortcut")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Tour.ink2)
                    ShortcutRecorderField(shortcut: model.binding(\.shortcut)) { isRecording in
                        if isRecording { hotkeys.pause() } else { hotkeys.resume() }
                    }
                    .frame(width: 210, height: 26)
                    Spacer()
                }
                .padding(.top, 12)
                .transition(.opacity.combined(with: .offset(y: -6)))
            }

            status

            HStack {
                TourLink(title: "Back") { tour.back() }
                Spacer()
                TourButton(title: "Use \(tour.shortcutText)") { tour.advance() }
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 22)
        .animation(Tour.settle, value: tour.shortcutChoice)
        .animation(Tour.settle, value: hotkeys.status)
    }

    private func option(_ choice: OnboardingModel.ShortcutChoice, _ title: String, _ detail: String, badge: String? = nil, keys: String) -> some View {
        let on = tour.shortcutChoice == choice
        return Button {
            tour.choose(choice)
        } label: {
            HStack(alignment: .top, spacing: 13) {
                ZStack {
                    Circle().strokeBorder(on ? Tour.cool : Tour.ink.opacity(0.35), lineWidth: 1.5)
                    Circle().fill(Tour.cool).frame(width: 9, height: 9).scaleEffect(on ? 1 : 0.01)
                }
                .frame(width: 18, height: 18)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title).font(.system(size: 13.5, weight: .semibold))
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Tour.cool)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Tour.cool.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Tour.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(keys)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(on ? Tour.ink : Tour.ink2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(on ? 0.24 : 0.14)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(on ? Tour.cool.opacity(0.09) : Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(on ? Tour.cool.opacity(0.42) : Color.white.opacity(0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(PressScale())
    }

    @ViewBuilder
    private var status: some View {
        switch hotkeys.status {
        case .needsInputMonitoring:
            notice(
                "macOS only shows \(tour.shortcutText) to apps allowed under Input Monitoring. Blink looks for the shortcut and nothing else.",
                tint: Tour.warning, action: "Allow…"
            ) { hotkeys.requestInputMonitoring() }
        case .unavailable:
            notice("Another app or the system already uses \(tour.shortcutText). Pick something else.", tint: Tour.warning)
        case .active, .inactive:
            if model.settings.shortcut.isFunctionKeyAlone, GlobeKey.hasSystemAction {
                notice(
                    "fn also opens the emoji picker. Set “Press 🌐 key to” to “Do Nothing” so it only opens Blink.",
                    tint: Tour.ink2, action: "Keyboard Settings…"
                ) { SystemSettings.openKeyboard() }
            }
        }
    }

    private func notice(_ text: String, tint: Color, action: String? = nil, perform: @escaping () -> Void = {}) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action {
                TourLink(title: action, action: perform)
                    .fixedSize()
            }
        }
        .padding(.top, 12)
        .transition(.opacity.combined(with: .offset(y: -4)))
    }
}

// MARK: - 5 · A starting board

private struct BoardStep: View {
    @ObservedObject var tour: OnboardingModel

    var body: some View {
        HStack(spacing: 16) {
            Text("STEP 4 OF 4")
                .font(Tour.caption)
                .tracking(0.9)
                .foregroundStyle(Tour.ink3)
                .fixedSize()
            if let kept = tour.kept {
                Tick()
                Text("\(kept.name) is your board. Move, resize or remove anything on it whenever you like.")
                    .font(.system(size: 13))
                    .foregroundStyle(Tour.ink.opacity(0.86))
                    .lineLimit(2)
                Spacer(minLength: 8)
                TourButton(title: "Continue") { tour.advance() }
            } else if tour.putBack || tour.trying == nil {
                Text("Your board is as it was.")
                    .font(.system(size: 13))
                    .foregroundStyle(Tour.ink.opacity(0.86))
                Spacer(minLength: 8)
                TourLink(title: "Try templates again") { tour.startTrying() }
                TourButton(title: "Continue") { tour.advance() }
            } else if let trying = tour.trying {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trying.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(trying.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(Tour.ink2)
                        .lineLimit(2)
                }
                .id(trying.id)
                .transition(.opacity.combined(with: .offset(y: 4)))
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    ForEach(BoardTemplate.all) { template in
                        Button { tour.startTrying(template) } label: {
                            Capsule()
                                .fill(template.id == trying.id ? Tour.cool : Color.white.opacity(0.22))
                                .frame(width: template.id == trying.id ? 22 : 8, height: 8)
                                .contentShape(Rectangle().inset(by: -4))
                        }
                        .buttonStyle(.plain)
                        .help(template.name)
                    }
                }
                TourLink(title: "Skip") { tour.advance() }
                TourButton(title: "Use \(trying.name)", arrow: false, height: 32) { tour.keepTrying() }
            }
        }
        .animation(Tour.settle, value: tour.trying?.id)
        .animation(Tour.settle, value: tour.kept?.id)
        .padding(.horizontal, 20)
        .frame(height: 76)
    }
}

// MARK: - 6 · What Blink can show

private struct AccessStep: View {
    @ObservedObject var tour: OnboardingModel
    @ObservedObject private var events = EventKitService.shared
    @ObservedObject private var messages = MessagesService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What Blink can show you")
                .font(Tour.title)
                .tracking(-0.4)
            Text("Each is asked for once, and only if you want it. Your things stay on this Mac, and every widget asks again when you add it.")
                .font(Tour.body)
                .lineSpacing(2.5)
                .foregroundStyle(Tour.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            VStack(spacing: 0) {
                row(symbol: "calendar", tint: Color(red: 0.74, green: 0.78, blue: 0.85), title: "Calendar",
                    detail: "Today’s events and the week ahead.") {
                    eventAccess(.event, allowed: events.canReadEvents, settings: SystemSettings.openCalendars)
                }
                .arrive(after: 0.08)
                divider
                row(symbol: "checklist", tint: Color(red: 0.9, green: 0.7, blue: 0.43), title: "Reminders",
                    detail: "What is due, ready to tick off.") {
                    eventAccess(.reminder, allowed: events.canReadReminders, settings: SystemSettings.openReminders)
                }
                .arrive(after: 0.14)
                divider
                row(symbol: "message.fill", tint: Tour.green, title: "Messages",
                    detail: "Your conversations, and replies without switching apps. Needs Contacts, for names, and Full Disk Access.") {
                    messagesAccess
                }
                .arrive(after: 0.2)
                divider
                row(symbol: "power", tint: Tour.ink, title: "Open at login",
                    detail: tour.loginProblem ?? "Blink is there whenever you reach for the keys.") {
                    Toggle("", isOn: $tour.opensAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(Tour.cool)
                        .controlSize(.small)
                }
                .arrive(after: 0.26)
            }
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.07)))
            .padding(.top, 20)

            HStack(spacing: 16) {
                TourLink(title: "Back") { tour.back() }
                Spacer()
                TourLink(title: "Skip for now") { tour.advance() }
                TourButton(title: "Continue") {
                    tour.applyLoginChoice()
                    tour.advance()
                }
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .animation(Tour.settle, value: events.canReadEvents)
        .animation(Tour.settle, value: events.canReadReminders)
        .animation(Tour.settle, value: messages.access)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from System Settings: see what changed there.
            events.refreshAuthorization()
            if messages.isAllowed { messages.refresh() }
        }
    }

    private var divider: some View {
        Rectangle().fill(Tour.hairline).frame(height: 1).padding(.leading, 64)
    }

    private func row<Trailing: View>(symbol: String, tint: Color, title: String, detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Tour.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func eventAccess(_ type: EKEntityType, allowed: Bool, settings: @escaping () -> Void) -> some View {
        if allowed {
            allowedLabel
        } else if events.isDenied(type) {
            pill("Open Settings…", action: settings)
        } else {
            pill("Allow…") { events.requestAccess(to: type) }
        }
    }

    @ViewBuilder
    private var messagesAccess: some View {
        if messages.isAllowed, messages.access == .granted {
            allowedLabel
        } else if messages.isAllowed, messages.access == .needsFullDiskAccess {
            pill("Turn On…") { SystemSettings.openFullDiskAccess() }
        } else {
            pill("Allow…") { messages.allowAccess() }
        }
    }

    private var allowedLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark").font(.system(size: 9.5, weight: .heavy))
            Text("Allowed").font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Tour.green)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Tour.green.opacity(0.1), in: Capsule())
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tour.cool)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Tour.cool.opacity(0.13), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .fixedSize()
        .transition(.opacity)
    }
}

// MARK: - 7 · You're set

private struct ReadyStep: View {
    @ObservedObject var tour: OnboardingModel

    var body: some View {
        let shortcut = tour.caps.map(\.symbol)
        let keys: [([String], String, String)] = [
            (shortcut, "Hold", "Peek, then let go"),
            (shortcut, "Tap", "Stay open to click"),
            (["esc"], "Close", "Or tap the keys again"),
            (["⌘", "N"], "Add", "A site, widget or file"),
            (["⌘", "E"], "Arrange", "Move, stack, resize"),
            (["←", "→"], "Templates", "Step along the shelf"),
        ]
        VStack(spacing: 0) {
            AnimatedMark(size: 56)
                .padding(.top, 36)
            Text("You are set")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.8)
                .padding(.top, 18)
                .arrive(after: 0.3)
            Text("Your board is one key away, whatever you are doing.")
                .font(Tour.body)
                .foregroundStyle(Tour.ink2)
                .padding(.top, 6)
                .arrive(after: 0.38)

            VStack(alignment: .leading, spacing: 14) {
                Text("YOUR KEYS")
                    .font(Tour.caption)
                    .tracking(0.9)
                    .foregroundStyle(Tour.ink3)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .leading), count: 3), alignment: .leading, spacing: 16) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                        HStack(spacing: 10) {
                            HStack(spacing: 3) {
                                ForEach(Array(key.0.enumerated()), id: \.offset) { _, cap in SmallCap(label: cap) }
                            }
                            .frame(minWidth: 52, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(key.1).font(.system(size: 12.5, weight: .semibold))
                                Text(key.2)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Tour.ink3)
                                    .lineLimit(1)
                            }
                        }
                        .arrive(after: 0.5 + Double(index) * 0.05)
                    }
                }
            }
            .padding(18)
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.05)))
            .padding(.top, 26)

            HStack(spacing: 12) {
                Text("The tour is in Blink’s menu whenever you want it again.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tour.ink3)
                Spacer()
                TourButton(title: "Start Using Blink", arrow: false, height: 38) { tour.advance() }
            }
            .padding(.top, 22)
            .arrive(after: 0.85)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
    }
}
