import AppKit
import BlinkCore
import Contacts
import CoreServices
import SQLite3

/// One conversation in the Messages widget's list.
struct Conversation: Identifiable, Hashable, Sendable {
    let id: Int64
    /// How Messages names the chat, which is also how it is sent to.
    let guid: String
    let title: String
    /// Phone numbers and addresses of the people in it.
    let handles: [String]
    let isGroup: Bool
    let lastText: String
    let lastDate: Date
    let lastFromMe: Bool
    let unread: Int
}

/// One message in an open conversation.
struct ChatMessage: Identifiable, Hashable, Sendable {
    let id: Int64
    let text: String
    let date: Date
    let fromMe: Bool
    /// Who sent it, in a group.
    let sender: String?
}

/// The Messages widget's one link to Messages. Conversations are read from
/// the database Messages keeps on this Mac, which macOS opens only to apps
/// with Full Disk Access; nothing is changed in it. Replies go through
/// Messages itself, which macOS asks about the first time.
@MainActor
final class MessagesService: ObservableObject {
    static let shared = MessagesService()

    enum Access: Equatable {
        case unknown
        case granted
        /// The database could not be opened: Full Disk Access is off.
        case needsFullDiskAccess
    }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var conversations: [Conversation] = []
    /// Bumped whenever the conversations were read again, so an open thread
    /// can read its messages again too.
    @Published private(set) var revision = 0
    @Published private(set) var canShowNames = false

    private let queue = DispatchQueue(label: "Blink.messages", qos: .userInitiated)
    private var names: [String: String] = [:]
    private var watcher: DispatchSourceFileSystemObject?
    private var isOverlayVisible = false
    private var isStale = true
    private var isLoading = false
    private var sample: SampleData?

    struct SampleData {
        var conversations: [Conversation]
        var threads: [Int64: [ChatMessage]]
    }

    private init() {
        canShowNames = CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db")
    }

    /// Stand-in conversations for the self-check, which cannot be given
    /// Full Disk Access.
    func useSampleData(_ data: SampleData) {
        sample = data
        access = .granted
        canShowNames = true
        conversations = data.conversations
        revision += 1
    }

    // MARK: - Reading

    /// Reads again only when something may have changed since last time.
    func refreshIfNeeded() {
        if isStale || access != .granted { refresh() }
    }

    func refresh() {
        guard sample == nil, !isLoading else { return }
        isLoading = true
        isStale = false
        let names = names
        queue.async {
            let result = MessagesService.readConversations(names: names)
            DispatchQueue.main.async {
                onMainActor {
                    self.isLoading = false
                    switch result {
                    case .success(let conversations):
                        self.access = .granted
                        self.conversations = conversations
                        self.revision += 1
                        self.watch()
                    case .failure:
                        self.access = .needsFullDiskAccess
                    }
                }
            }
        }
    }

    /// The widget is only read while it can be seen; a change while the
    /// overlay is hidden waits for it to open.
    func overlayVisibilityChanged(_ visible: Bool) {
        isOverlayVisible = visible
        if visible { refreshIfNeeded() }
    }

    func messages(in conversation: Conversation, completion: @escaping @MainActor @Sendable ([ChatMessage]) -> Void) {
        if let sample {
            completion(sample.threads[conversation.id] ?? [])
            return
        }
        let names = names
        let id = conversation.id
        queue.async {
            let messages = MessagesService.readMessages(chat: id, names: names)
            DispatchQueue.main.async {
                onMainActor { completion(messages) }
            }
        }
    }

    /// Messages writes to its database as messages arrive. Watching its
    /// journal means the list is read again only when there is news.
    private func watch() {
        guard watcher == nil else { return }
        let path = MessagesService.databaseURL.path + "-wal"
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: .main
        )
        source.setEventHandler { [weak self] in
            onMainActor {
                guard let self, let watcher = self.watcher else { return }
                if !watcher.data.isDisjoint(with: [.delete, .rename]) {
                    // The journal was replaced: watch the new one.
                    watcher.cancel()
                    self.watcher = nil
                    self.isStale = true
                    return
                }
                self.isStale = true
                if self.isOverlayVisible {
                    // A burst of writes becomes one read.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        onMainActor { self.refreshIfNeeded() }
                    }
                }
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    // MARK: - Names

    /// Shows the system prompt for Contacts. The overlay steps aside first,
    /// or the prompt would open underneath it.
    func requestNames() {
        NotificationCenter.default.post(name: .blinkDismissOverlay, object: nil)
        CNContactStore().requestAccess(for: .contacts) { granted, _ in
            DispatchQueue.main.async {
                onMainActor {
                    self.canShowNames = granted
                    if granted { self.loadNames() }
                }
            }
        }
    }

    func loadNamesIfAllowed() {
        if canShowNames, names.isEmpty { loadNames() }
    }

    private func loadNames() {
        queue.async {
            let names = MessagesService.readContactNames()
            DispatchQueue.main.async {
                onMainActor {
                    self.names = names
                    self.isStale = true
                    self.refresh()
                }
            }
        }
    }

    nonisolated private static func readContactNames() -> [String: String] {
        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
        ] as [CNKeyDescriptor]
        var names: [String: String] = [:]
        let request = CNContactFetchRequest(keysToFetch: keys)
        try? CNContactStore().enumerateContacts(with: request) { contact, _ in
            let person = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let name = person.isEmpty ? contact.organizationName : person
            guard !name.isEmpty else { return }
            for number in contact.phoneNumbers {
                if let key = MessageText.phoneKey(number.value.stringValue) { names[key] = name }
            }
            for address in contact.emailAddresses {
                names[(address.value as String).lowercased()] = name
            }
        }
        return names
    }

    nonisolated private static func name(for handle: String, in names: [String: String]) -> String? {
        if let key = MessageText.phoneKey(handle), let name = names[key] { return name }
        return names[handle.lowercased()]
    }

    // MARK: - Sending

    /// Sends through Messages. The first time, macOS asks whether Blink may
    /// do that; the overlay steps aside so the question can be seen.
    func send(_ text: String, to conversation: Conversation, completion: @escaping @MainActor @Sendable (String?) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if sample != nil {
            completion(nil)
            return
        }
        if MessagesService.needsAutomationConsent() {
            NotificationCenter.default.post(name: .blinkDismissOverlay, object: nil)
        }
        let guid = conversation.guid
        queue.async {
            let error = MessagesService.runSend(trimmed, chat: guid)
            DispatchQueue.main.async {
                onMainActor {
                    completion(error)
                    self.isStale = true
                    // Messages takes a moment to write what it sent.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        onMainActor { self.refreshIfNeeded() }
                    }
                }
            }
        }
    }

    /// True unless macOS has already been told Blink may use Messages.
    private static func needsAutomationConsent() -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.MobileSMS")
        guard let descriptor = target.aeDesc else { return true }
        let status = AEDeterminePermissionToAutomateTarget(
            descriptor, AEEventClass(typeWildCard), AEEventID(typeWildCard), false
        )
        return status != noErr
    }

    /// The message and the chat go in as arguments, never into the script's
    /// text, so nothing in a message can change what the script does.
    nonisolated private static func runSend(_ text: String, chat: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "on run argv",
            "-e", "tell application \"Messages\" to send (item 1 of argv) to chat id (item 2 of argv)",
            "-e", "end run",
            text, chat,
        ]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            return error.localizedDescription
        }
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if output.contains("-1743") {
            return "Blink is not allowed to send with Messages. Allow it in System Settings, Privacy & Security, Automation."
        }
        return "Messages could not send this."
    }

    // MARK: - The database

    private struct ReadFailure: Error {}

    nonisolated private static func readConversations(names: [String: String]) -> Result<[Conversation], ReadFailure> {
        guard let database = MessagesDatabase(url: databaseURL) else { return .failure(ReadFailure()) }

        struct Row {
            var id: Int64, guid: String, identifier: String, displayName: String
            var text: String?, body: [UInt8], date: Int64, fromMe: Bool
        }
        var rows: [Row] = []
        // The newest twenty chats, each with its newest real message (not a
        // tapback or a change to the group).
        let ok = database.query("""
            SELECT c.ROWID, c.guid, c.chat_identifier, IFNULL(c.display_name, ''),
                   m.text, m.attributedBody, m.date, m.is_from_me
            FROM chat c
            JOIN message m ON m.ROWID = (
                SELECT j.message_id FROM chat_message_join j
                JOIN message x ON x.ROWID = j.message_id
                WHERE j.chat_id = c.ROWID AND x.item_type = 0 AND x.associated_message_type = 0
                ORDER BY j.message_id DESC LIMIT 1)
            ORDER BY m.date DESC
            LIMIT 20
            """) { row in
            rows.append(Row(
                id: row.int(0), guid: row.text(1), identifier: row.text(2), displayName: row.text(3),
                text: row.optionalText(4), body: row.blob(5), date: row.int(6), fromMe: row.int(7) != 0
            ))
        }
        guard ok else { return .failure(ReadFailure()) }

        // Unread messages from the last fortnight; older ones were seen elsewhere.
        var unread: [Int64: Int] = [:]
        let since = MessageText.messagesTime(from: Date().addingTimeInterval(-14 * 86_400))
        for row in rows {
            _ = database.query("""
                SELECT COUNT(*) FROM chat_message_join j JOIN message u ON u.ROWID = j.message_id
                WHERE j.chat_id = ? AND u.is_read = 0 AND u.is_from_me = 0
                  AND u.item_type = 0 AND u.associated_message_type = 0 AND u.date > ?
                """, bind: [row.id, since]) { unread[row.id] = Int($0.int(0)) }
        }

        let conversations = rows.map { row -> Conversation in
            var handles: [String] = []
            _ = database.query("""
                SELECT h.id FROM chat_handle_join j JOIN handle h ON h.ROWID = j.handle_id WHERE j.chat_id = ?
                """, bind: [row.id]) { handles.append($0.text(0)) }
            if handles.isEmpty { handles = [row.identifier] }
            let isGroup = handles.count > 1
            let people = handles.map { name(for: $0, in: names) ?? $0 }
            let title: String
            if !row.displayName.isEmpty {
                title = row.displayName
            } else if isGroup {
                title = MessageText.groupTitle(people)
            } else {
                title = people.first ?? row.identifier
            }
            return Conversation(
                id: row.id, guid: row.guid, title: title, handles: handles, isGroup: isGroup,
                lastText: MessageText.display(text: row.text, attributedBody: row.body),
                lastDate: MessageText.date(fromMessagesTime: row.date),
                lastFromMe: row.fromMe, unread: unread[row.id] ?? 0
            )
        }
        return .success(conversations)
    }

    nonisolated private static func readMessages(chat: Int64, names: [String: String]) -> [ChatMessage] {
        guard let database = MessagesDatabase(url: databaseURL) else { return [] }
        var messages: [ChatMessage] = []
        _ = database.query("""
            SELECT m.ROWID, m.text, m.attributedBody, m.date, m.is_from_me, IFNULL(h.id, '')
            FROM chat_message_join j JOIN message m ON m.ROWID = j.message_id
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE j.chat_id = ? AND m.item_type = 0 AND m.associated_message_type = 0
            ORDER BY j.message_id DESC LIMIT 60
            """, bind: [chat]) { row in
            let handle = row.text(5)
            messages.append(ChatMessage(
                id: row.int(0),
                text: MessageText.display(text: row.optionalText(1), attributedBody: row.blob(2)),
                date: MessageText.date(fromMessagesTime: row.int(3)),
                fromMe: row.int(4) != 0,
                sender: handle.isEmpty ? nil : (name(for: handle, in: names) ?? handle)
            ))
        }
        return messages.reversed()
    }
}

/// A read-only connection to the Messages database, opened for one read.
private final class MessagesDatabase {
    private var handle: OpaquePointer?

    init?(url: URL) {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
        sqlite3_busy_timeout(handle, 500)
    }

    deinit {
        sqlite3_close(handle)
    }

    struct Row {
        let statement: OpaquePointer

        func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }

        func text(_ column: Int32) -> String { optionalText(column) ?? "" }

        func optionalText(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }

        func blob(_ column: Int32) -> [UInt8] {
            guard let bytes = sqlite3_column_blob(statement, column) else { return [] }
            let count = Int(sqlite3_column_bytes(statement, column))
            return Array(UnsafeRawBufferPointer(start: bytes, count: count))
        }
    }

    /// Runs `sql` and hands over each row. False if it could not be run,
    /// which is what happens without Full Disk Access.
    func query(_ sql: String, bind values: [Int64] = [], row: (Row) -> Void) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            sqlite3_bind_int64(statement, Int32(index + 1), value)
        }
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: row(Row(statement: statement))
            case SQLITE_DONE: return true
            default: return false
            }
        }
    }
}
