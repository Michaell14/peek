import AppKit
import EventKit
import SwiftUI

struct EventItem: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let location: String?
}

struct ReminderItem: Identifiable, Hashable {
    let id: String
    let title: String
    let due: Date?
    /// False when the reminder is due on a day rather than at a time.
    let hasTime: Bool
    let listName: String
    let color: Color
}

/// The app's one connection to Calendar and Reminders.
@MainActor
final class EventKitService: ObservableObject {
    static let shared = EventKitService()

    /// Bumped whenever calendar or reminder data may have changed.
    @Published private(set) var revision = 0
    @Published private(set) var canReadEvents = false
    @Published private(set) var canReadReminders = false

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    /// Stand-in data, used instead of the real stores once set.
    private var sample: SampleData?

    /// Calendar and reminder data that does not come from the user's
    /// accounts. The self-check uses it to exercise the widgets, since an
    /// automated run cannot be granted access to the real thing.
    struct SampleData {
        var events: [EventItem]
        var reminders: [ReminderItem]
    }

    func useSampleData(_ data: SampleData) {
        sample = data
        canReadEvents = true
        canReadReminders = true
        revision += 1
    }

    private init() {
        refreshAuthorization()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            onMainActor { self?.revision += 1 }
        }
    }

    /// True once the user has answered the system prompt with "no".
    func isDenied(_ type: EKEntityType) -> Bool {
        switch EKEventStore.authorizationStatus(for: type) {
        case .denied, .restricted, .writeOnly: return true
        default: return false
        }
    }

    /// Shows the system permission prompt. The overlay is dismissed first
    /// because the prompt would open underneath it.
    func requestAccess(to type: EKEntityType) {
        NotificationCenter.default.post(name: .blinkDismissOverlay, object: nil)
        let completion: EKEventStoreRequestAccessCompletionHandler = { @Sendable [weak self] _, _ in
            DispatchQueue.main.async {
                onMainActor {
                    guard let self else { return }
                    self.store.reset()
                    self.refreshAuthorization()
                    self.revision += 1
                }
            }
        }
        if type == .reminder {
            store.requestFullAccessToReminders(completion: completion)
        } else {
            store.requestFullAccessToEvents(completion: completion)
        }
    }

    func refreshAuthorization() {
        guard sample == nil else { return }
        canReadEvents = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        canReadReminders = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    // MARK: - Calendar

    func events(from start: Date, to end: Date) -> [EventItem] {
        if let sample {
            return sample.events.filter { $0.end > start && $0.start < end }.sorted { $0.start < $1.start }
        }
        guard canReadEvents else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .map { event in
                let start: Date = event.startDate ?? Date()
                let end: Date = event.endDate ?? start
                let identifier: String = event.eventIdentifier ?? UUID().uuidString
                let title: String = event.title ?? ""
                return EventItem(
                    // Repeating events share an identifier, so add the start.
                    id: "\(identifier)-\(start.timeIntervalSince1970)",
                    title: title.isEmpty ? "Untitled" : title,
                    start: start,
                    end: end,
                    isAllDay: event.isAllDay,
                    color: Color(nsColor: event.calendar?.color ?? .systemBlue),
                    location: event.location
                )
            }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    // MARK: - Reminders

    func fetchReminders(completion: @escaping @MainActor @Sendable ([ReminderItem]) -> Void) {
        if let sample {
            completion(sample.reminders)
            return
        }
        guard canReadReminders else {
            completion([])
            return
        }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        _ = store.fetchReminders(matching: predicate) { @Sendable reminders in
            // Runs on a background queue: reduce to plain values here.
            let calendar = Calendar.current
            let items = (reminders ?? []).map { reminder -> ReminderItem in
                let components = reminder.dueDateComponents
                let title: String = reminder.title ?? ""
                return ReminderItem(
                    id: reminder.calendarItemIdentifier,
                    title: title.isEmpty ? "Untitled" : title,
                    due: components.flatMap { calendar.date(from: $0) },
                    hasTime: components?.hour != nil,
                    listName: reminder.calendar?.title ?? "",
                    color: Color(nsColor: reminder.calendar?.color ?? .systemBlue)
                )
            }
            DispatchQueue.main.async {
                onMainActor { completion(items) }
            }
        }
    }

    func complete(_ id: String) {
        if sample != nil {
            sample?.reminders.removeAll { $0.id == id }
            revision += 1
            return
        }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        save(reminder)
    }

    func addReminder(title: String, dueToday: Bool) {
        if sample != nil {
            let due = dueToday ? Calendar.current.startOfDay(for: Date()) : nil
            sample?.reminders.append(ReminderItem(
                id: UUID().uuidString, title: title, due: due, hasTime: false, listName: "Reminders", color: .blue
            ))
            revision += 1
            return
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()
        if dueToday {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        }
        save(reminder)
    }

    private func save(_ reminder: EKReminder) {
        do {
            try store.save(reminder, commit: true)
        } catch {
            NSLog("Blink: could not save reminder: \(error.localizedDescription)")
        }
        revision += 1
    }
}

/// Shown in place of a widget until the user lets it read its data.
struct AccessPrompt: View {
    let symbol: String
    let name: String
    let isDenied: Bool
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.blinkAccent)
                .frame(width: 44, height: 44)
                .background(Color.blinkAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if isDenied {
                Text("Blink is not allowed to read \(name). You can change that in System Settings → Privacy & Security.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Open System Settings", action: openSettings)
                    .buttonStyle(AccentButtonStyle())
            } else {
                VStack(spacing: 3) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                    Text("Show your \(name.lowercased()) here. They stay on this Mac.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("Allow Access…", action: request)
                    .buttonStyle(AccentButtonStyle())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
