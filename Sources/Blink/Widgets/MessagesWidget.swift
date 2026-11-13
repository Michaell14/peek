import BlinkCore
import Contacts
import SwiftUI

/// Messages' own colours, as it draws them in dark mode.
private enum IMessage {
    static let blue = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let green = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let received = Color(white: 0.23)
    static let secondary = Color(white: 0.6)
    static let field = Color.white.opacity(0.06)
    static let hairline = Color.white.opacity(0.08)
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.86)
}

/// Recent conversations from Messages, looking as they do there. Choose one
/// to read it and reply without leaving what you were doing.
@MainActor
struct MessagesWidgetView: View {
    let config: MessagesConfig

    @ObservedObject private var service = MessagesService.shared
    @State private var openID: Int64?
    @State private var search = ""

    init(config: MessagesConfig) {
        self.config = config
    }

    var body: some View {
        Group {
            if !service.isAllowed || service.access == .needsFullDiskAccess {
                MessagesSetupView()
            } else if service.access == .unknown {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let open = service.conversations.first(where: { $0.id == openID }) {
                MessagesThreadView(conversation: open) {
                    withAnimation(IMessage.spring) { openID = nil }
                }
                .transition(.move(edge: .trailing))
            } else {
                list
                    .transition(.move(edge: .leading))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .onAppear {
            service.loadNamesIfAllowed()
            service.refreshIfNeeded()
        }
    }

    private var shown: [Conversation] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return service.conversations }
        return service.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.lastText.localizedCaseInsensitiveContains(query)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IMessage.secondary)
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(IMessage.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if shown.isEmpty {
                Text(service.conversations.isEmpty ? "No Conversations" : "No Results")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(IMessage.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, conversation in
                            Button {
                                withAnimation(IMessage.spring) { openID = conversation.id }
                            } label: {
                                ConversationRow(conversation: conversation, isLast: index == shown.count - 1)
                            }
                            .buttonStyle(RowButtonStyle())
                        }
                    }
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.never)
            }
        }
    }
}

/// A row that darkens a little while pressed, as Messages' do.
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.06) : Color.clear)
    }
}

/// Messages' avatar: initials on a grey disc, or a silhouette.
private struct Avatar: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        let initials = MessageText.initials(for: name)
        ZStack {
            Circle().fill(LinearGradient(
                colors: [Color(white: 0.64), Color(white: 0.44)], startPoint: .top, endPoint: .bottom
            ))
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.white.opacity(0.95))
                    .offset(y: size * 0.06)
                    .mask(Circle())
            } else {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isLast: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Unread: a blue dot in the margin.
            Circle()
                .fill(conversation.unread > 0 ? IMessage.blue : Color.clear)
                .frame(width: 8, height: 8)
                .frame(width: 18)
            Avatar(name: conversation.title)
                .padding(.trailing, 10)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(conversation.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(MessageText.shortTime(conversation.lastDate, now: Date()))
                        .font(.system(size: 11))
                        .foregroundStyle(IMessage.secondary)
                        .monospacedDigit()
                }
                Text(conversation.lastText)
                    .font(.system(size: 12))
                    .foregroundStyle(IMessage.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 9)
            .padding(.trailing, 12)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(IMessage.hairline).frame(height: 0.5)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - A conversation

/// One conversation, newest at the bottom, with a field to reply.
private struct MessagesThreadView: View {
    let conversation: Conversation
    let close: () -> Void

    @ObservedObject private var service = MessagesService.shared
    @State private var messages: [ChatMessage] = []
    @State private var reply = ""
    @State private var isSending = false
    @State private var problem: String?

    private var bubbleColour: Color { conversation.isTextMessage ? IMessage.green : IMessage.blue }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(IMessage.hairline).frame(height: 0.5)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            row(index, message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
                .scrollIndicators(.never)
                .defaultScrollAnchor(.bottom)
                .onChange(of: messages) { _, updated in
                    if let last = updated.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            if let problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.4))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            composer
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

    /// The person at the top, as on iPhone, with the way back on the left.
    private var header: some View {
        ZStack {
            VStack(spacing: 3) {
                Avatar(name: conversation.title, size: 30)
                HStack(spacing: 2) {
                    Text(conversation.title)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(IMessage.secondary)
                }
            }
            HStack {
                Button(action: close) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(IMessage.blue)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back to conversations")
                Spacer()
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func row(_ index: Int, _ message: ChatMessage) -> some View {
        let previous = index > 0 ? messages[index - 1] : nil
        let next = index < messages.count - 1 ? messages[index + 1] : nil
        // A pause of a quarter of an hour gets the time above it.
        let showsTime = previous.map { message.date.timeIntervalSince($0.date) > 900 } ?? true
        let startsGroup = showsTime || previous?.fromMe != message.fromMe || previous?.sender != message.sender
        let endsGroup = next.map { next in
            next.fromMe != message.fromMe || next.sender != message.sender || next.date.timeIntervalSince(message.date) > 900
        } ?? true

        if showsTime {
            Text(Self.stamp(message.date))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(IMessage.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, index == 0 ? 0 : 10)
                .padding(.bottom, 6)
        }
        if conversation.isGroup, !message.fromMe, startsGroup, let sender = message.sender {
            Text(sender)
                .font(.system(size: 10.5))
                .foregroundStyle(IMessage.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 44)
                .padding(.top, showsTime ? 0 : 6)
                .padding(.bottom, 2)
        }
        HStack(alignment: .bottom, spacing: 6) {
            if message.fromMe {
                Spacer(minLength: 48)
            } else if conversation.isGroup {
                // In a group, who said it, beside the last of their run.
                Group {
                    if endsGroup { Avatar(name: message.sender ?? "", size: 26) } else { Color.clear }
                }
                .frame(width: 26, height: 26)
            }
            Text(message.text)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    BubbleShape(fromMe: message.fromMe, hasTail: endsGroup)
                        .fill(message.fromMe ? bubbleColour : IMessage.received)
                )
                .textSelection(.enabled)
            if !message.fromMe { Spacer(minLength: 48) }
        }
        .padding(.top, startsGroup && !showsTime ? 8 : 2)
        if message.fromMe, index == messages.count - 1, !conversation.isTextMessage, let status = Self.status(of: message) {
            Text(status)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(IMessage.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 2)
                .padding(.trailing, 4)
        }
    }

    /// "Today 9:41 AM", "Yesterday 4:10 PM", "Tuesday 9:41 AM", "Nov 3 at 9:41 AM".
    private static func stamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday \(time)" }
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())), date >= weekAgo {
            return "\(date.formatted(.dateTime.weekday(.wide))) \(time)"
        }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())) at \(time)"
    }

    /// Under the last message sent: "Read 9:42 AM" or "Delivered".
    private static func status(of message: ChatMessage) -> String? {
        if let read = message.readDate {
            let calendar = Calendar.current
            return calendar.isDateInToday(read)
                ? "Read \(read.formatted(date: .omitted, time: .shortened))"
                : "Read \(read.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return message.isDelivered ? "Delivered" : nil
    }

    private var composer: some View {
        HStack(spacing: 0) {
            TextField(conversation.isTextMessage ? "Text Message" : "iMessage", text: $reply)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit(send)
                .padding(.leading, 12)
                .padding(.vertical, 6)
            if canSend {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 21))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, bubbleColour)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 3)
                .help("Send")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(minHeight: 28)
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: canSend)
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 10)
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

/// A message bubble: a rounded body and, on the last of a run, the tail that
/// curls out of its bottom corner.
private struct BubbleShape: Shape {
    let fromMe: Bool
    let hasTail: Bool

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let radius = min(17, h / 2)
        var path = Path()
        path.addRoundedRect(in: CGRect(x: 0, y: 0, width: w, height: h), cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        if hasTail {
            path.move(to: CGPoint(x: w - 0.5, y: h - 17))
            path.addQuadCurve(to: CGPoint(x: w + 6, y: h), control: CGPoint(x: w, y: h - 3))
            path.addQuadCurve(to: CGPoint(x: w - 15, y: h - 0.5), control: CGPoint(x: w - 5, y: h + 1.2))
            path.closeSubpath()
        }
        if !fromMe {
            // Received messages curl the other way.
            path = path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0))
        }
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

// MARK: - Asking first

/// What the widget needs, asked before anything is read.
private struct MessagesSetupView: View {
    @ObservedObject private var service = MessagesService.shared

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            // Messages' own icon: a white bubble on green.
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.4, green: 0.92, blue: 0.45), Color(red: 0.1, green: 0.75, blue: 0.27)],
                        startPoint: .top, endPoint: .bottom
                    ))
                Image(systemName: "message.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)

            VStack(spacing: 5) {
                Text("Messages in Blink")
                    .font(.system(size: 15, weight: .semibold))
                Text("See your conversations and reply without leaving what you are doing. Your messages stay on this Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(IMessage.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                need(
                    symbol: "person.crop.circle",
                    title: "Contacts",
                    detail: "So conversations show names, not numbers.",
                    state: contactsState
                )
                need(
                    symbol: "lock.shield",
                    title: "Full Disk Access",
                    detail: "The only way macOS lets an app read Messages. You turn it on for Blink in System Settings.",
                    state: service.access == .granted ? .done : (service.isAllowed ? .waiting : .notYet)
                )
            }
            .padding(12)
            .background(IMessage.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if service.isAllowed {
                Button("Open System Settings") {
                    NotificationCenter.default.post(name: .blinkDismissOverlay, object: nil)
                    SystemSettings.openFullDiskAccess()
                }
                .buttonStyle(BlueButtonStyle())
                Button("Check Again") { service.refresh() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(IMessage.blue)
            } else {
                Button("Allow Access…") { service.allowAccess() }
                    .buttonStyle(BlueButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private enum NeedState { case notYet, waiting, done, refused }

    private var contactsState: NeedState {
        switch service.contacts {
        case .authorized: return .done
        case .notDetermined: return .notYet
        default: return service.isAllowed ? .refused : .notYet
        }
    }

    private func need(symbol: String, title: String, detail: String, state: NeedState) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(IMessage.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    switch state {
                    case .done:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(IMessage.green)
                    case .refused:
                        Text("Not allowed: numbers are shown")
                            .foregroundStyle(IMessage.secondary)
                    case .waiting, .notYet:
                        EmptyView()
                    }
                }
                .font(.system(size: 11))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(IMessage.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct BlueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 28)
            .background(IMessage.blue.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}
