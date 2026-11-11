import BlinkCore
import SwiftUI

@MainActor
struct ClockWidgetView: View {
    let config: ClockConfig
    let onChange: (ClockConfig) -> Void

    @State private var isAddingCity = false

    init(config: ClockConfig, onChange: @escaping (ClockConfig) -> Void) {
        self.config = config
        self.onChange = onChange
    }

    private var uses24Hour: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return !format.contains("a")
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let rows = config.zones.compactMap {
                WorldClock.row(identifier: $0, at: timeline.date, local: .current, uses24Hour: uses24Hour)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        ClockRowView(row: row)
                            .contextMenu {
                                Button("Remove \(row.city)") { remove(row.id) }
                                    .disabled(config.zones.count <= 1)
                            }
                        if index < rows.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 1)
                                .padding(.leading, 44)
                        }
                    }
                    Button {
                        isAddingCity = true
                    } label: {
                        Label("Add City", systemImage: "plus")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isAddingCity, arrowEdge: .bottom) {
                        TimeZonePicker(existing: config.zones) { identifier in
                            isAddingCity = false
                            add(identifier)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func add(_ identifier: String) {
        guard !config.zones.contains(identifier) else { return }
        onChange(ClockConfig(zones: config.zones + [identifier]))
    }

    private func remove(_ identifier: String) {
        let zones = config.zones.filter { $0 != identifier }
        guard !zones.isEmpty else { return }
        onChange(ClockConfig(zones: zones))
    }
}

private struct ClockRowView: View {
    let row: WorldClock.Row

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Sun or moon: whether it is a sensible hour to call.
            Image(systemName: row.isDaytime ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 11))
                .foregroundStyle(row.isDaytime ? Color.blinkAccent : Color.blinkCool)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.city)
                    .font(.system(size: 14, weight: .semibold))
                Text(row.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(row.time)
                    .font(.system(size: 27, weight: .light, design: .rounded))
                    .monospacedDigit()
                if !row.period.isEmpty {
                    Text(row.period)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(height: 59)
        .contentShape(Rectangle())
    }
}

private struct TimeZonePicker: View {
    let existing: [String]
    let onPick: (String) -> Void

    @State private var search = ""
    @FocusState private var isSearchFocused: Bool

    private var matches: [String] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let candidates = TimeZone.knownTimeZoneIdentifiers.filter { !existing.contains($0) }
        guard !query.isEmpty else { return candidates }
        return candidates.filter {
            $0.lowercased().replacingOccurrences(of: "_", with: " ").contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search cities", text: $search)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
            List(matches, id: \.self) { identifier in
                Button {
                    onPick(identifier)
                } label: {
                    HStack {
                        Text(WorldClock.cityName(for: identifier))
                        Spacer()
                        Text(identifier.split(separator: "/").first.map(String.init) ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .padding(10)
        .frame(width: 280, height: 340)
        .onAppear { isSearchFocused = true }
    }
}
