import BlinkCore
import SwiftUI

/// Recent conversations from Messages. Choose one to read it and reply
/// without leaving what you were doing.
@MainActor
struct MessagesWidgetView: View {
    let config: MessagesConfig

    @ObservedObject private var service = MessagesService.shared
    @State private var openID: Int64?

    init(config: MessagesConfig) {
        self.config = config
    }

    var body: some View {
        Group {
            switch service.access {
            case .granted:
                if let open = service.conversations.first(where: { $0.id == openID }) {
                    MessagesThreadView(conversation: open) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { openID = nil }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    list
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            case .needsFullDiskAccess:
                MessagesAccessPrompt()
            case .unknown:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .onAppear {
            service.loadNamesIfAllowed()
            service.refreshIfNeeded()
        }
    }

    private var list: some View {
        let unread = service.conversations.reduce(0) { $0 + $1.unread }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SectionLabel("Recent")
                Spacer(minLength: 0)
                if !service.canShowNames {
                    Button("Show Names…") { service.requestNames() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .help("Blink can show names from Contacts instead of numbers")
                }
                if unread > 0 {
                    Text("\(unread) unread")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.blinkAccent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            if service.conversations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "message")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No conversations yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(service.conversations) { conversation in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { openID = conversation.id }
                            } label: {
                                ConversationRow(conversation: conversation)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.never)
            }
        }
    }
}

/// Initials on a tinted circle; a person for numbers and addresses.
private struct Avatar: View {
    let name: String
    var size: CGFloat = 32

    /// Each person keeps the same tint every time.
    private var tint: Color {
        let tints: [Color] = [.blinkCool, .blinkAccent, Color(red: 0.45, green: 0.8, blue: 0.55), Color(red: 0.92, green: 0.62, blue: 0.5)]
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return tints[sum % tints.count]
    }

    var body: some View {
        let initials = MessageText.initials(for: name)
        ZStack {
            Circle().fill(tint.opacity(0.28))
            Circle().strokeBorder(tint.opacity(0.35), lineWidth: 0.5)
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
            }
        }
        .foregroundStyle(.primary)
        .frame(width: size, height: size)
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 10) {
            Avatar(name: conversation.title)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(MessageText.shortTime(conversation.lastDate, now: Date()))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack(spacing: 6) {
                    Text((conversation.lastFromMe ? "You: " : "") + conversation.lastText)
                        .font(.system(size: 12))
                        .foregroundStyle(conversation.unread > 0 ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if conversation.unread > 0 {
                        Circle()
                            .fill(Color.blinkAccent)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("Unread")
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

/// One conversation, newest at the bottom, with a field to reply.
private struct MessagesThreadView: View {
    let conversation: Conversation
    let close: () -> Void

    @ObservedObject private var service = MessagesService.shared
    @State private var messages: [ChatMessage] = []
    @State private var reply = ""
    @State private var isSending = false
    @State private var problem: String?
    @FocusState private var isReplying: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: close) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back to conversations")
                Avatar(name: conversation.title, size: 24)
                Text(conversation.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(messages) { message in
                            Bubble(message: message, showsSender: conversation.isGroup)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.never)
                .onChange(of: messages) { _, updated in
                    if let last = updated.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            if let problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 6) {
                TextField("Message", text: $reply)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($isReplying)
                    .onSubmit(send)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(canSend ? Color.blinkAccent : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("Send")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .task(id: ReloadKey(conversation: conversation.id, revision: service.revision)) {
            service.messages(in: conversation) { fetched in
                messages = fetched
            }
        }
    }

    private struct ReloadKey: Hashable {
        var conversation: Int64
        var revision: Int
    }

    private var canSend: Bool {
        !isSending && !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        let text = reply
        isSending = true
        problem = nil
        service.send(text, to: conversation) { error in
            isSending = false
            if let error {
                problem = error
            } else {
                reply = ""
            }
        }
    }
}

private struct Bubble: View {
    let message: ChatMessage
    let showsSender: Bool

    var body: some View {
        HStack {
            if message.fromMe { Spacer(minLength: 36) }
            VStack(alignment: message.fromMe ? .trailing : .leading, spacing: 2) {
                if showsSender, !message.fromMe, let sender = message.sender {
                    Text(sender)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
                Text(message.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(message.fromMe ? Color.black.opacity(0.85) : Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        message.fromMe ? Color.blinkAccent : Color.white.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    .textSelection(.enabled)
            }
            if !message.fromMe { Spacer(minLength: 36) }
        }
    }
}

/// Shown until Blink may read Messages.
private struct MessagesAccessPrompt: View {
    @ObservedObject private var service = MessagesService.shared

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "message")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.blinkAccent)
                .frame(width: 44, height: 44)
                .background(Color.blinkAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(spacing: 4) {
                Text("Messages")
                    .font(.system(size: 14, weight: .semibold))
                Text("Show your recent conversations here and reply from Blink. macOS lets an app read Messages only with Full Disk Access, which you turn on for Blink in System Settings. Your messages stay on this Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Open System Settings") {
                NotificationCenter.default.post(name: .blinkDismissOverlay, object: nil)
                SystemSettings.openFullDiskAccess()
            }
            .buttonStyle(AccentButtonStyle())
            Button("Check Again") { service.refresh() }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
