import EventKit
import BlinkCore
import SwiftUI

@MainActor
struct RemindersWidgetView: View {
    let config: RemindersConfig
    let onChange: (RemindersConfig) -> Void

    @ObservedObject private var service = EventKitService.shared
    @State private var items: [ReminderItem] = []
    @State private var newTitle = ""
    /// Reminders ticked off a moment ago, shown struck through before they go.
    @State private var completing: Set<String> = []

    init(config: RemindersConfig, onChange: @escaping (RemindersConfig) -> Void) {
        self.config = config
        self.onChange = onChange
    }

    private struct ReloadKey: Hashable {
        var revision: Int
        var isAuthorized: Bool
    }

    var body: some View {
        Group {
            if service.canReadReminders {
                content
            } else {
                AccessPrompt(
                    symbol: "checklist",
                    name: "Reminders",
                    isDenied: service.isDenied(.reminder),
                    request: { service.requestAccess(to: .reminder) },
                    openSettings: SystemSettings.openReminders
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: ReloadKey(revision: service.revision, isAuthorized: service.canReadReminders)) {
            service.fetchReminders { fetched in
                items = fetched
                completing.formIntersection(fetched.map(\.id))
            }
        }
    }

    private var content: some View {
        let sections = ReminderSections.make(from: items, filter: config.filter, now: Date())
        let count = sections.reduce(0) { $0 + $1.items.count }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Shorter labels when the tile is too narrow for the full ones.
                ViewThatFits(in: .horizontal) {
                    filterPicker(scheduled: "Scheduled", overdue: "Overdue")
                    filterPicker(scheduled: "Later", overdue: "Late")
                }
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(count == 0 ? Color.secondary : Color.blinkAccent)
            }
            .padding(.horizontal, 12)
            .padding(.top, 11)
            .padding(.bottom, 7)

            if sections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("All done")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sections) { section in
                            SectionLabel(section.title)
                                .padding(.horizontal, 14)
                                .padding(.top, 9)
                                .padding(.bottom, 3)
                            ForEach(section.items) { item in
                                row(item)
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.never)
            }

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                TextField("New Reminder", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .onSubmit { addReminder() }
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
        }
    }

    private func filterPicker(scheduled: String, overdue: String) -> some View {
        PillPicker(
            options: [
                (RemindersConfig.Filter.today, "Today"),
                (RemindersConfig.Filter.scheduled, scheduled),
                (RemindersConfig.Filter.overdue, overdue),
                (RemindersConfig.Filter.all, "All"),
            ],
            selection: config.filter,
            onChange: { onChange(RemindersConfig(filter: $0)) }
        )
    }

    private func row(_ item: ReminderItem) -> some View {
        let isDone = completing.contains(item.id)
        return HStack(alignment: .top, spacing: 9) {
            Button {
                complete(item)
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(item.color, lineWidth: 1.5)
                    if isDone {
                        Circle()
                            .fill(item.color)
                            .padding(3.5)
                    }
                }
                .frame(width: 17, height: 17)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDone)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12.5))
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .lineLimit(3)
                if let due = item.due {
                    Text(ReminderSections.dueText(due, hasTime: item.hasTime, now: Date()))
                        .font(.system(size: 10.5))
                        .foregroundStyle(ReminderSections.isOverdue(item, now: Date()) ? Color.red : Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }

    private func complete(_ item: ReminderItem) {
        completing.insert(item.id)
        // Leave the tick visible for a beat, as Reminders itself does.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            onMainActor { EventKitService.shared.complete(item.id) }
        }
    }

    private func addReminder() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        service.addReminder(title: title, dueToday: config.filter == .today)
        newTitle = ""
    }
}

/// Groups reminders the way each filter presents them.
enum ReminderSections {
    struct Section: Identifiable {
        var id: String { title }
        var title: String
        var items: [ReminderItem]
    }

    static func isOverdue(_ item: ReminderItem, now: Date) -> Bool {
        guard let due = item.due else { return false }
        // A reminder due "today" with no time is not overdue until tomorrow.
        return item.hasTime ? due < now : due < Calendar.current.startOfDay(for: now)
    }

    static func make(from items: [ReminderItem], filter: RemindersConfig.Filter, now: Date) -> [Section] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let byDue: (ReminderItem, ReminderItem) -> Bool = {
            ($0.due ?? .distantFuture, $0.title) < ($1.due ?? .distantFuture, $1.title)
        }
        let overdue = items.filter { isOverdue($0, now: now) }.sorted(by: byDue)

        var sections: [Section] = []
        switch filter {
        case .today:
            let earlier = items.filter { ($0.due ?? .distantFuture) < startOfToday }.sorted(by: byDue)
            let today = items.filter { item in
                guard let due = item.due else { return false }
                return due >= startOfToday && due < startOfTomorrow
            }.sorted(by: byDue)
            sections = [Section(title: "Overdue", items: earlier), Section(title: "Today", items: today)]
        case .overdue:
            sections = [Section(title: "Overdue", items: overdue)]
        case .scheduled:
            let scheduled = items.filter { $0.due != nil }.sorted(by: byDue)
            let byDay = Dictionary(grouping: scheduled) { calendar.startOfDay(for: $0.due ?? now) }
            sections = byDay.keys.sorted().map { day in
                Section(title: dayTitle(day, today: startOfToday), items: byDay[day] ?? [])
            }
        case .all:
            let byList = Dictionary(grouping: items.sorted(by: byDue), by: \.listName)
            sections = byList.keys.sorted().map { Section(title: $0.isEmpty ? "Reminders" : $0, items: byList[$0] ?? []) }
        }
        return sections.filter { !$0.items.isEmpty }
    }

    static func dayTitle(_ day: Date, today: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: today) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    static func dueText(_ due: Date, hasTime: Bool, now: Date) -> String {
        let day = dayTitle(Calendar.current.startOfDay(for: due), today: Calendar.current.startOfDay(for: now))
        return hasTime ? "\(day), \(due.formatted(date: .omitted, time: .shortened))" : day
    }
}
