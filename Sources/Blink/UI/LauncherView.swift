import BlinkCore
import SwiftUI

/// The "add something" sheet: an address field plus widgets, files and a few
/// starting points.
struct LauncherView: View {
    let searchTemplate: String
    let onAddWebsite: (URL) -> Void
    let onAddWidget: (WidgetContent) -> Void
    let onChooseFile: () -> Void

    @State private var address = ""
    @FocusState private var isAddressFocused: Bool

    private struct Choice: Identifiable {
        let id: String
        let name: String
        let symbol: String
    }

    private static let widgets = [
        Choice(id: "clock", name: "Clock", symbol: "clock"),
        Choice(id: "calendar", name: "Calendar", symbol: "calendar"),
        Choice(id: "reminders", name: "Reminders", symbol: "checklist"),
        Choice(id: "notes", name: "Notes", symbol: "note.text"),
    ]

    private static let sites = [
        Choice(id: "https://github.com", name: "GitHub", symbol: "chevron.left.forwardslash.chevron.right"),
        Choice(id: "https://mail.google.com", name: "Gmail", symbol: "envelope"),
        Choice(id: "https://calendar.google.com", name: "Google Calendar", symbol: "calendar.badge.clock"),
        Choice(id: "https://linear.app", name: "Linear", symbol: "list.bullet.rectangle"),
        Choice(id: "https://www.notion.so", name: "Notion", symbol: "doc.text"),
        Choice(id: "https://news.ycombinator.com", name: "Hacker News", symbol: "newspaper"),
        Choice(id: "https://www.youtube.com", name: "YouTube", symbol: "play.rectangle"),
        Choice(id: "https://en.wikipedia.org", name: "Wikipedia", symbol: "book"),
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                TextField("Search or enter a website address", text: $address)
                    .textFieldStyle(.plain)
                    .focused($isAddressFocused)
                    .onSubmit { submit() }
                Button("Add") { submit() }
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(.system(size: 16))
            .padding(10)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            section("Widgets") {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Self.widgets) { choice in
                        tile(choice) { onAddWidget(Self.widget(for: choice.id)) }
                    }
                }
            }

            section("Files") {
                Button(action: onChooseFile) {
                    Label("Choose a PDF or HTML File…", systemImage: "doc")
                }
            }

            section("Websites") {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Self.sites) { choice in
                        tile(choice) {
                            if let url = URL(string: choice.id) { onAddWebsite(url) }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.14)))
        .onAppear {
            // Focus has to wait until the view is in the window.
            DispatchQueue.main.async { isAddressFocused = true }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func tile(_ choice: Choice, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: choice.symbol)
                    .font(.system(size: 18))
                    .frame(height: 22)
                Text(choice.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private static func widget(for id: String) -> WidgetContent {
        switch id {
        case "calendar": return .calendar(CalendarConfig())
        case "reminders": return .reminders(RemindersConfig())
        case "notes": return .notes(NotesConfig())
        default: return .clock(ClockConfig())
        }
    }

    private func submit() {
        guard let url = URLInput.resolve(address, searchTemplate: searchTemplate) else { return }
        onAddWebsite(url)
    }
}
