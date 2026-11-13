import AppKit
import BlinkCore
import EventKit
import SwiftUI

// The tour's colours: Blink's dark glass, a cool blue for what to press,
// and the amber of the lit tile.
private enum Tour {
    static let ink = Color(red: 0.95, green: 0.953, blue: 0.96)
    static let ink2 = Color(red: 0.886, green: 0.902, blue: 0.933).opacity(0.74)
    static let ink3 = Color(red: 0.886, green: 0.902, blue: 0.933).opacity(0.62)
    static let cool = Color(red: 0.616, green: 0.729, blue: 1.0)
    static let onCool = Color(red: 0.04, green: 0.07, blue: 0.15)
    static let lit = Color(red: 1.0, green: 0.78, blue: 0.38)
    static let green = Color(red: 0.24, green: 0.86, blue: 0.52)
    static let warning = Color(red: 1.0, green: 0.6, blue: 0.57)
    static let arrive = Animation.spring(response: 0.42, dampingFraction: 0.86)
}

struct OnboardingView: View {
    @ObservedObject var tour: OnboardingModel
    @ObservedObject var model: AppModel
    @ObservedObject var hotkeys: HotkeyMonitor

    /// The window's size for each step.
    static func size(for step: OnboardingModel.Step) -> CGSize {
        switch step {
        case .hello: return CGSize(width: 520, height: 492)
        case .hold: return CGSize(width: 600, height: 236)
        case .tap: return CGSize(width: 600, height: 276)
        case .shortcut: return CGSize(width: 660, height: 610)
        case .board: return CGSize(width: 800, height: 76)
        case .access: return CGSize(width: 640, height: 488)
        case .ready: return CGSize(width: 740, height: 430)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.white.opacity(0.09), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom)
            Color(red: 0.055, green: 0.06, blue: 0.07).opacity(0.62)
            content
                .id(tour.step)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 12)).animation(Tour.arrive.delay(0.1)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .foregroundStyle(Tour.ink)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// The one filled button: cool blue, dark text, an arrow when it moves on.
private struct TourButton: View {
    let title: String
    var arrow = true
    var height: CGFloat = 36
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if arrow {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .offset(x: isHovering ? 2 : 0)
                }
            }
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(Tour.onCool)
            .padding(.horizontal, 18)
            .frame(height: height)
            .background(Tour.cool.opacity(isHovering ? 1 : 0.92), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
        .keyboardShortcut(.defaultAction)
    }
}

private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
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
        .onHover { isHovering = $0 }
    }
}

/// "STEP 2 OF 4", the four segments, and Skip.
private struct StepHeader: View {
    let number: Int
    var skip: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Text("STEP \(number) OF 4")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Tour.ink3)
                .fixedSize()
            HStack(spacing: 4) {
                ForEach(1...4, id: \.self) { segment in
                    Capsule()
                        .fill(segment <= number ? Tour.cool : Color.white.opacity(0.12))
                        .frame(height: 3)
                }
            }
            if let skip {
                TourLink(title: "Skip", action: skip)
            }
        }
    }
}

private struct Tick: View {
    @State private var shown = false

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Tour.green)
            .frame(width: 22, height: 22)
            .background(Tour.green.opacity(0.18), in: Circle())
            .scaleEffect(shown ? 1 : 0.4)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { shown = true } }
    }
}

/// A key drawn large, the way it looks on the keyboard.
private struct BigCap: View {
    let key: OnboardingKey
    var size: CGFloat = 74
    var pressed = false
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
                    colors: [Color(red: 0.165, green: 0.172, blue: 0.196), Color(red: 0.13, green: 0.137, blue: 0.157)],
                    startPoint: .top, endPoint: .bottom
                ))
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .strokeBorder(pressed ? Tour.cool.opacity(0.6) : Color.white.opacity(0.22), lineWidth: 1)
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
                .offset(y: pressed ? 1 : 4)
        )
        .shadow(color: pressed ? Tour.cool.opacity(0.3) : Color.black.opacity(0.45), radius: pressed ? 14 : 12, y: pressed ? 0 : 10)
        .offset(y: pressed ? 2 : 0)
        .animation(.easeOut(duration: 0.08), value: pressed)
        .animation(.easeOut(duration: 0.12), value: lit)
    }
}

/// A key drawn small, for the cheat sheet.
private struct SmallCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .frame(minWidth: 24, minHeight: 24)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.165, green: 0.172, blue: 0.196), Color(red: 0.13, green: 0.137, blue: 0.157)],
                    startPoint: .top, endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: 0.047, green: 0.055, blue: 0.07))
                    .offset(y: 2)
            )
    }
}

/// Blink's mark, built up tile by tile, the lit one glowing.
private struct AnimatedMark: View {
    var size: CGFloat = 76
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
                    .animation(Tour.arrive.delay(0.15), value: shown)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(0.42))
                    .offset(x: shown ? 0 : -size * 0.2)
                    .opacity(shown ? 1 : 0)
                    .animation(Tour.arrive.delay(0.25), value: shown)
            }
            .frame(width: size * 0.37)
            RoundedRectangle(cornerRadius: radius * 1.1, style: .continuous)
                .fill(Tour.lit)
                .phaseAnimator([false, true]) { tile, glowing in
                    tile.shadow(color: Tour.lit.opacity(glowing ? 0.5 : 0.25), radius: glowing ? size * 0.38 : size * 0.22)
                } animation: { _ in .easeInOut(duration: 1.8) }
                .scaleEffect(shown ? 1 : 0.5, anchor: .bottom)
                .opacity(shown ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.4), value: shown)
        }
        .frame(width: size, height: size)
        .onAppear { shown = true }
    }
}

/// A gentle bob, for a hint waiting to be acted on.
private struct Nudge: ViewModifier {
    func body(content: Content) -> some View {
        content.phaseAnimator([0.0, -3.0]) { view, offset in
            view.offset(y: offset)
        } animation: { _ in .easeInOut(duration: 0.8) }
    }
}

/// Appears a moment after the view does, rising slightly.
private struct Arrive: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear { withAnimation(Tour.arrive.delay(delay)) { shown = true } }
    }
}

private extension View {
    func arrive(after delay: Double) -> some View { modifier(Arrive(delay: delay)) }
}

private struct CapsRow: View {
    let caps: [OnboardingKey]
    var pressed = false
    var size: CGFloat = 74

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, key in
                BigCap(key: key, size: size, pressed: pressed, lit: pressed && key.name != nil)
            }
        }
    }
}

private func capsPhrase(_ caps: [OnboardingKey]) -> String {
    caps.map(\.symbol).joined(separator: " and ")
}

// MARK: - 1 · Hello

private struct HelloStep: View {
    @ObservedObject var tour: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            AnimatedMark()
                .padding(.top, 50)
            Text("Blink")
                .font(.system(size: 42, weight: .semibold))
                .tracking(-1)
                .padding(.top, 22)
                .arrive(after: 0.5)
            Text("Everything you check all day, one key away. Hold it to look, let go to get back to work.")
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(Tour.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .arrive(after: 0.6)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(["Hold to peek", "Tap to keep it open", "Choose your key and board", "Say what it may show"].enumerated()), id: \.offset) { index, label in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tour.cool)
                            .frame(width: 22, height: 22)
                            .background(Tour.cool.opacity(0.14), in: Circle())
                        Text(label)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Tour.ink.opacity(0.9))
                    }
                    .arrive(after: 0.75 + Double(index) * 0.07)
                }
            }
            .padding(.top, 26)

            Spacer(minLength: 16)

            HStack {
                TourLink(title: "Skip the tour") { tour.skipTour() }
                Spacer()
                TourButton(title: "Get Started") { tour.advance() }
            }
            .arrive(after: 1.05)
            Text("About a minute. Skip any step, and find the tour again in Blink’s menu.")
                .font(.system(size: 11.5))
                .foregroundStyle(Tour.ink3)
                .padding(.top, 14)
                .arrive(after: 1.1)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }
}

// MARK: - 2 · Hold to peek

private struct HoldStep: View {
    @ObservedObject var tour: OnboardingModel
    @ObservedObject var hotkeys: HotkeyMonitor

    var body: some View {
        let title = words.0
        let detail = words.1
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(number: 1) { tour.advance() }
            HStack(spacing: 22) {
                CapsRow(caps: tour.caps, pressed: tour.isPeeking)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 21, weight: .semibold))
                        .tracking(-0.3)
                        .contentTransition(.opacity)
                    Text(detail)
                        .font(.system(size: 13.5))
                        .lineSpacing(2)
                        .foregroundStyle(Tour.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                .animation(.easeOut(duration: 0.18), value: title)
            }
            .padding(.top, 16)
            Spacer(minLength: 10)
            footer
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 18)
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
            "Blink comes up over whatever you are doing while the keys are down. Try it now, on your own desktop."
        )
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            if hotkeys.status == .needsInputMonitoring {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tour.warning)
                Text("macOS has to let Blink see \(tour.shortcutText) first.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tour.ink2)
                Spacer()
                TourLink(title: "Allow…") { hotkeys.requestInputMonitoring() }
            } else if hotkeys.status == .unavailable {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tour.warning)
                Text("Another app already uses \(tour.shortcutText). Choose a different key in step 3.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tour.ink2)
                Spacer()
                TourButton(title: "Continue") { tour.advance() }
            } else if tour.isPeeking {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Let go to get back")
                        .font(.system(size: 12.5))
                }
                .foregroundStyle(Tour.cool)
                Spacer()
            } else if tour.peeks > 0 {
                Tick()
                Text(tour.peeks == 1 ? "One peek. Try it again, or carry on." : "\(tour.peeks) peeks. You have the hang of it.")
                    .font(.system(size: 13))
                    .foregroundStyle(Tour.ink.opacity(0.82))
                    .contentTransition(.numericText())
                Spacer()
                TourButton(title: "Continue") { tour.advance() }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Press and hold the real keys")
                        .font(.system(size: 12.5))
                }
                .foregroundStyle(Tour.ink3)
                .modifier(Nudge())
                Spacer()
            }
        }
        .frame(height: 36)
    }
}

// MARK: - 3 · Tap to keep it open

private struct TapStep: View {
    @ObservedObject var tour: OnboardingModel

    var body: some View {
        let title = words.0
        let detail = words.1
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(number: 2) { tour.advance() }
            HStack(spacing: 22) {
                CapsRow(caps: tour.caps, pressed: tour.isPeeking || tour.isPinned)
                    .overlay {
                        if !tour.openedPinned {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Tour.cool.opacity(0.7), lineWidth: 1.5)
                                .padding(-6)
                                .phaseAnimator([false, true]) { ring, out in
                                    ring.scaleEffect(out ? 1.08 : 1).opacity(out ? 0 : 0.9)
                                } animation: { out in out ? .easeOut(duration: 1.2) : .linear(duration: 0.01) }
                        }
                    }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 21, weight: .semibold))
                        .tracking(-0.3)
                    Text(detail)
                        .font(.system(size: 13.5))
                        .lineSpacing(2)
                        .foregroundStyle(Tour.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .animation(.easeOut(duration: 0.18), value: title)
            }
            .padding(.top, 16)

            HStack(spacing: 8) {
                task("Tap to keep it open", done: tour.openedPinned)
                task("Tap again or esc to close", done: tour.closedAfterPin)
            }
            .padding(.top, 16)

            Spacer(minLength: 10)
            HStack(spacing: 10) {
                if tour.openedPinned, tour.closedAfterPin, !tour.isPinned {
                    Tick()
                    Text("Both ways, done.")
                        .font(.system(size: 13))
                        .foregroundStyle(Tour.ink.opacity(0.82))
                    Spacer()
                    TourButton(title: "Continue") { tour.advance() }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                        Text(tour.isPinned ? "Tap \(tour.shortcutText) again, or press esc" : "Press \(tour.shortcutText) and let go straight away")
                            .font(.system(size: 12.5))
                    }
                    .foregroundStyle(Tour.ink3)
                    .modifier(Nudge())
                    Spacer()
                }
            }
            .frame(height: 36)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }

    private var words: (String, String) {
        if tour.isPinned {
            return ("It stays open", "The bar along the top has Add, Templates, Arrange and Settings. Tap again, or press esc, to close.")
        }
        if tour.openedPinned, tour.closedAfterPin {
            return ("Peek, or keep it open", "Hold when you only need a look; tap when you want to stay a while.")
        }
        return ("Now tap instead", "A quick tap keeps Blink open, so you can click, scroll and type in any tile. Holding still peeks.")
    }

    private func task(_ label: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .strokeBorder(done ? Tour.green : Tour.ink.opacity(0.4), lineWidth: 1.5)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Tour.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 16, height: 16)
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(done ? Tour.ink : Tour.ink2)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(done ? Tour.green.opacity(0.12) : Color.white.opacity(0.05), in: Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: done)
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
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.5)
                .padding(.top, 20)
            Text("Pick something your fingers find without looking. You can change it any time in Settings.")
                .font(.system(size: 14))
                .foregroundStyle(Tour.ink2)
                .padding(.top, 6)

            // The shortcut, drawn as the keys themselves.
            HStack(spacing: 10) {
                CapsRow(caps: tour.caps, size: 64)
                    .id(model.settings.shortcut)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85).combined(with: .opacity).combined(with: .offset(y: -10)),
                        removal: .opacity
                    ))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 108)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
            .animation(.spring(response: 0.36, dampingFraction: 0.72), value: model.settings.shortcut)
            .padding(.top, 20)

            VStack(spacing: 8) {
                option(.standard, "Option and the key above Tab", "Works the moment Blink opens. Nothing to allow.",
                       badge: "Recommended", keys: Shortcut.default.displayString)
                option(.function, "fn on its own", "One key, easy to reach. macOS asks you to allow Input Monitoring first.",
                       keys: "fn")
                option(.custom, "Something else", "Any combination, or one modifier on its own, such as the right ⌘.",
                       keys: tour.shortcutChoice == .custom ? tour.shortcutText : "Record…")
            }
            .padding(.top, 16)

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
                .padding(.top, 10)
                .transition(.opacity.combined(with: .offset(y: -6)))
            }

            status
                .padding(.top, 10)

            Spacer(minLength: 8)
            HStack {
                TourLink(title: "Back") { tour.back() }
                Spacer()
                TourButton(title: "Use \(tour.shortcutText)") { tour.advance() }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 26)
        .padding(.bottom, 24)
    }

    private func option(_ choice: OnboardingModel.ShortcutChoice, _ title: String, _ detail: String, badge: String? = nil, keys: String) -> some View {
        let on = tour.shortcutChoice == choice
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tour.choose(choice) }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().strokeBorder(on ? Tour.cool : Tour.ink.opacity(0.4), lineWidth: 1.5)
                    Circle().fill(Tour.cool).frame(width: 10, height: 10).scaleEffect(on ? 1 : 0.01)
                }
                .frame(width: 20, height: 20)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title).font(.system(size: 14, weight: .semibold))
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Tour.cool)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Tour.cool.opacity(0.16), in: Capsule())
                        }
                    }
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Tour.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(keys)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Tour.ink2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.16)))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(on ? Tour.cool.opacity(0.10) : Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(on ? Tour.cool.opacity(0.45) : Color.white.opacity(0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var status: some View {
        switch hotkeys.status {
        case .needsInputMonitoring:
            HStack(spacing: 10) {
                Text("macOS only shows \(tour.shortcutText) to apps allowed under Input Monitoring. Blink looks for the shortcut and nothing else.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tour.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                TourLink(title: "Allow…") { hotkeys.requestInputMonitoring() }
            }
        case .unavailable:
            Text("Another app or the system already uses \(tour.shortcutText). Pick something else.")
                .font(.system(size: 12))
                .foregroundStyle(Tour.warning)
        case .active, .inactive:
            if model.settings.shortcut.isFunctionKeyAlone, GlobeKey.hasSystemAction {
                HStack(spacing: 10) {
                    Text("fn also opens the emoji picker. Set “Press 🌐 key to” to “Do Nothing” so it only opens Blink.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tour.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    TourLink(title: "Keyboard Settings…") { SystemSettings.openKeyboard() }
                }
            }
        }
    }
}

// MARK: - 5 · A starting board

private struct BoardStep: View {
    @ObservedObject var tour: OnboardingModel

    var body: some View {
        HStack(spacing: 16) {
            Text("STEP 4 OF 4")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
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
                    Text("Try a starting board")
                        .font(.system(size: 13, weight: .semibold))
                    Text(trying.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(Tour.ink2)
                        .lineLimit(2)
                        .id(trying.id)
                        .transition(.opacity)
                }
                .animation(.easeOut(duration: 0.18), value: trying.id)
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
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: trying.id)
                TourLink(title: "Skip") { tour.advance() }
                TourButton(title: "Use \(trying.name)", arrow: false, height: 32) { tour.keepTrying() }
            }
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity)
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
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.5)
            Text("Each is asked for once, here, and only if you want it. Your things stay on this Mac. Skip any of them; the widgets ask again when you add them.")
                .font(.system(size: 14))
                .lineSpacing(2)
                .foregroundStyle(Tour.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(spacing: 8) {
                row(symbol: "calendar", tint: Color(red: 0.74, green: 0.78, blue: 0.85), title: "Calendar",
                    detail: "Today’s events and the week ahead.") {
                    eventAccess(.event, allowed: events.canReadEvents, settings: SystemSettings.openCalendars)
                }
                .arrive(after: 0.1)
                row(symbol: "checklist", tint: Color(red: 0.9, green: 0.7, blue: 0.43), title: "Reminders",
                    detail: "What is due, ready to tick off.") {
                    eventAccess(.reminder, allowed: events.canReadReminders, settings: SystemSettings.openReminders)
                }
                .arrive(after: 0.16)
                row(symbol: "message.fill", tint: Tour.green, title: "Messages",
                    detail: "Your conversations, and replies without switching apps. Asks for Contacts, for names, and Full Disk Access, to read Messages.") {
                    messagesAccess
                }
                .arrive(after: 0.22)
                row(symbol: "power", tint: Tour.ink, title: "Open at login",
                    detail: tour.loginProblem ?? "Blink is there whenever you reach for the keys.") {
                    Toggle("", isOn: $tour.opensAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(Tour.cool)
                }
                .arrive(after: 0.28)
            }
            .padding(.top, 20)

            Spacer(minLength: 12)
            HStack(spacing: 14) {
                TourLink(title: "Back") { tour.back() }
                Spacer()
                TourLink(title: "Skip for now") { tour.advance() }
                TourButton(title: "Continue") {
                    tour.applyLoginChoice()
                    tour.advance()
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from System Settings: see what changed there.
            events.refreshAuthorization()
            if messages.isAllowed { messages.refresh() }
        }
    }

    private func row<Trailing: View>(symbol: String, tint: Color, title: String, detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tour.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.07)))
    }

    @ViewBuilder
    private func eventAccess(_ type: EKEntityType, allowed: Bool, settings: @escaping () -> Void) -> some View {
        if allowed {
            allowedLabel
        } else if events.isDenied(type) {
            pill("Open Settings…", action: settings)
        } else {
            pill("Allow Access…") { events.requestAccess(to: type) }
        }
    }

    @ViewBuilder
    private var messagesAccess: some View {
        if messages.isAllowed, messages.access == .granted {
            allowedLabel
        } else if messages.isAllowed, messages.access == .needsFullDiskAccess {
            pill("Turn On Full Disk Access…") { SystemSettings.openFullDiskAccess() }
        } else {
            pill("Allow Access…") { messages.allowAccess() }
        }
    }

    private var allowedLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
            Text("Allowed").font(.system(size: 12.5, weight: .semibold))
        }
        .foregroundStyle(Tour.green)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Tour.cool)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Tour.cool.opacity(0.14), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .fixedSize()
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
            (["←", "→"], "Templates", "Flip while trying one"),
        ]
        VStack(spacing: 0) {
            AnimatedMark(size: 60)
                .padding(.top, 34)
            Text("You are set")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.6)
                .padding(.top, 18)
                .arrive(after: 0.3)
            Text("Your board is ready. It is one key away, whatever you are doing.")
                .font(.system(size: 14))
                .foregroundStyle(Tour.ink2)
                .padding(.top, 8)
                .arrive(after: 0.38)

            VStack(alignment: .leading, spacing: 14) {
                Text("YOUR KEYS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Tour.ink3)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .leading), count: 3), alignment: .leading, spacing: 14) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                        HStack(spacing: 10) {
                            HStack(spacing: 4) {
                                ForEach(Array(key.0.enumerated()), id: \.offset) { _, cap in SmallCap(label: cap) }
                            }
                            .frame(minWidth: 56, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(key.1).font(.system(size: 13, weight: .semibold))
                                Text(key.2)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Tour.ink3)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        }
                        .arrive(after: 0.55 + Double(index) * 0.05)
                    }
                }
            }
            .padding(18)
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
            .padding(.top, 24)

            Spacer(minLength: 12)
            HStack(spacing: 12) {
                Text("See this again any time: Blink Tour, in Blink’s menu.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tour.ink3)
                Spacer()
                TourButton(title: "Start Using Blink", arrow: false, height: 38) { tour.advance() }
            }
            .arrive(after: 0.9)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }
}
