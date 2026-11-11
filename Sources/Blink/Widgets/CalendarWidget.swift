import Combine
import EventKit
import BlinkCore
import SwiftUI

@MainActor
struct CalendarWidgetView: View {
    let config: CalendarConfig
    let onChange: (CalendarConfig) -> Void

    @ObservedObject private var service = EventKitService.shared
    @State private var today = Calendar.current.startOfDay(for: Date())
    @State private var events: [EventItem] = []

    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(config: CalendarConfig, onChange: @escaping (CalendarConfig) -> Void) {
        self.config = config
        self.onChange = onChange
    }

    /// Everything that should trigger a reload when it changes.
    private struct ReloadKey: Hashable {
        var revision: Int
        var mode: CalendarConfig.Mode
        var day: Date
        var isAuthorized: Bool
    }

    var body: some View {
        Group {
            if service.canReadEvents {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    switch config.mode {
                    case .day: DayTimelineView(day: today, events: events)
                    case .agenda: AgendaView(today: today, events: events)
                    }
                }
            } else {
                AccessPrompt(
                    symbol: "calendar",
                    name: "Calendar",
                    isDenied: service.isDenied(.event),
                    request: { service.requestAccess(to: .event) },
                    openSettings: SystemSettings.openCalendars
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: ReloadKey(revision: service.revision, mode: config.mode, day: today, isAuthorized: service.canReadEvents)) {
            reload()
        }
        .onReceive(minuteTimer) { now in
            // Roll over at midnight.
            let start = Calendar.current.startOfDay(for: now)
            if start != today { today = start }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            // A narrow tile gets "Wed 11" rather than a wrapped "Wednesday".
            ViewThatFits(in: .horizontal) {
                dateLabel(weekday: .wide, month: true)
                dateLabel(weekday: .abbreviated, month: true)
                dateLabel(weekday: .abbreviated, month: false)
            }
            Spacer(minLength: 4)
            Picker("View", selection: Binding(get: { config.mode }, set: { onChange(CalendarConfig(mode: $0)) })) {
                Text("Day").tag(CalendarConfig.Mode.day)
                Text("7 Days").tag(CalendarConfig.Mode.agenda)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func dateLabel(weekday: Date.FormatStyle.Symbol.Weekday, month: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(today.formatted(.dateTime.weekday(weekday)))
                .font(.system(size: 14, weight: .semibold))
            Text(month ? today.formatted(.dateTime.month(.abbreviated).day()) : today.formatted(.dateTime.day()))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func reload() {
        let calendar = Calendar.current
        let days = config.mode == .day ? 1 : 7
        let end = calendar.date(byAdding: .day, value: days, to: today) ?? today.addingTimeInterval(Double(days) * 86_400)
        events = service.events(from: today, to: end)
    }
}

// MARK: - Day

private struct DayTimelineView: View {
    let day: Date
    let events: [EventItem]

    private let hourHeight: CGFloat = 46
    private let gutter: CGFloat = 48

    var body: some View {
        let allDay = events.filter(\.isAllDay)
        let timed = events.filter { !$0.isAllDay }

        VStack(alignment: .leading, spacing: 0) {
            if !allDay.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(allDay) { event in
                        Text(event.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(event.color.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        hourGrid
                        GeometryReader { geometry in
                            blocks(for: timed, width: geometry.size.width)
                        }
                        TimelineView(.periodic(from: .now, by: 60)) { timeline in
                            nowLine(at: timeline.date)
                        }
                    }
                    .frame(height: hourHeight * 24)
                }
                .onAppear {
                    let hour = Calendar.current.component(.hour, from: Date())
                    proxy.scrollTo(max(hour - 1, 0), anchor: .top)
                }
            }
        }
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 6) {
                    Text(hourLabel(hour))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: gutter - 10, alignment: .trailing)
                        .offset(y: -6)
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        guard hour > 0 else { return "" }
        let date = day.addingTimeInterval(Double(hour) * 3600)
        return date.formatted(.dateTime.hour())
    }

    private func blocks(for events: [EventItem], width: CGFloat) -> some View {
        let spans = events.map { event -> (start: Double, end: Double) in
            let start = min(max(event.start.timeIntervalSince(day), 0), 86_400 - 900)
            let end = min(max(event.end.timeIntervalSince(day), start + 900), 86_400)
            return (start, end)
        }
        let slots = EventLayout.arrange(spans)
        let available = max(width - gutter - 8, 40)

        return ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
            let span = spans[index]
            let slot = slots[index]
            let columnWidth = available / CGFloat(slot.columnCount)
            EventBlockView(event: event)
                .frame(
                    width: max(columnWidth - 2, 10),
                    height: max(CGFloat(span.end - span.start) / 3600 * hourHeight - 2, 16),
                    alignment: .topLeading
                )
                .offset(
                    x: gutter + CGFloat(slot.column) * columnWidth,
                    y: CGFloat(span.start) / 3600 * hourHeight
                )
        }
    }

    @ViewBuilder
    private func nowLine(at date: Date) -> some View {
        let seconds = date.timeIntervalSince(day)
        if seconds >= 0, seconds < 86_400 {
            HStack(spacing: 0) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                Rectangle()
                    .fill(Color.red)
                    .frame(height: 1)
            }
            .padding(.leading, gutter - 4)
            .offset(y: CGFloat(seconds) / 3600 * hourHeight - 3.5)
        }
    }
}

private struct EventBlockView: View {
    let event: EventItem

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(event.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
            Text(event.start.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(event.color.opacity(0.3), in: RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color)
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Agenda

private struct AgendaView: View {
    let today: Date
    let events: [EventItem]

    private struct DayGroup: Identifiable {
        var id: Date
        var events: [EventItem]
    }

    private var groups: [DayGroup] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: events) { event in
            // An event that started earlier and is still running belongs to today.
            max(calendar.startOfDay(for: event.start), today)
        }
        return byDay.keys.sorted().map { DayGroup(id: $0, events: byDay[$0] ?? []) }
    }

    var body: some View {
        if events.isEmpty {
            Text("Nothing in the next 7 days")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        Text(dayLabel(group.id))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        ForEach(group.events) { event in
                            AgendaRowView(event: event)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: today) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

private struct AgendaRowView: View {
    let event: EventItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                Text(timeText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        if let location = event.location, !location.isEmpty {
            return "\(start) – \(end) · \(location)"
        }
        return "\(start) – \(end)"
    }
}
