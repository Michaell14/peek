import BlinkCore
import SwiftUI

/// What the launcher offers and which row is selected. The overlay owns it
/// so that the arrow keys and Return work whatever has keyboard focus.
@MainActor
final class LauncherModel: ObservableObject {
    struct Item: Identifiable, Equatable {
        enum Action: Equatable {
            case website(URL)
            case widget(WidgetContent)
            case chooseFile
            /// A ready-made board, by its id.
            case template(String)
        }

        enum Kind: String {
            case widget = "Widget"
            case file = "File"
            case template = "Template"
            case website = "Website"
            case search = "Search"
        }

        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let kind: Kind
        let action: Action
    }

    @Published var query = "" {
        didSet {
            if query != oldValue { selection = 0 }
        }
    }

    @Published var selection = 0

    var onWebsite: (URL) -> Void = { _ in }
    var onWidget: (WidgetContent) -> Void = { _ in }
    var onChooseFile: () -> Void = {}
    var onTemplate: (BoardTemplate) -> Void = { _ in }

    private let searchTemplate: String
    /// Set to show only one kind of item, such as templates.
    let scope: Item.Kind?

    init(searchTemplate: String, scope: Item.Kind? = nil) {
        self.searchTemplate = searchTemplate
        self.scope = scope
    }

    private static let catalog: [Item] = {
        var items = [
            Item(id: "widget.clock", title: "Clock", subtitle: "The time in the places you care about",
                 symbol: "clock", kind: .widget, action: .widget(.clock(ClockConfig()))),
            Item(id: "widget.calendar", title: "Calendar", subtitle: "Today's events, or the next seven days",
                 symbol: "calendar", kind: .widget, action: .widget(.calendar(CalendarConfig()))),
            Item(id: "widget.reminders", title: "Reminders", subtitle: "What is due, ready to tick off",
                 symbol: "checklist", kind: .widget, action: .widget(.reminders(RemindersConfig()))),
            Item(id: "widget.notes", title: "Notes", subtitle: "A scratchpad that is always there",
                 symbol: "note.text", kind: .widget, action: .widget(.notes(NotesConfig()))),
            Item(id: "widget.messages", title: "Messages", subtitle: "Recent conversations, and replies without switching apps",
                 symbol: "message", kind: .widget, action: .widget(.messages(MessagesConfig()))),
            Item(id: "file.choose", title: "PDF or HTML File…", subtitle: "Keep a document within reach",
                 symbol: "doc", kind: .file, action: .chooseFile),
        ]
        for template in BoardTemplate.all {
            items.append(Item(id: "template.\(template.id)", title: template.name, subtitle: template.summary,
                              symbol: template.symbol, kind: .template, action: .template(template.id)))
        }
        let sites: [(String, String, String)] = [
            ("GitHub", "github.com", "chevron.left.forwardslash.chevron.right"),
            ("Gmail", "mail.google.com", "envelope"),
            ("Google Calendar", "calendar.google.com", "calendar.badge.clock"),
            ("Linear", "linear.app", "list.bullet.rectangle"),
            ("Notion", "www.notion.so", "doc.text"),
            ("Hacker News", "news.ycombinator.com", "newspaper"),
            ("YouTube", "www.youtube.com", "play.rectangle"),
            ("Wikipedia", "en.wikipedia.org", "book"),
        ]
        for (name, host, symbol) in sites {
            guard let url = URL(string: "https://\(host)") else { continue }
            items.append(Item(id: "site.\(host)", title: name, subtitle: host,
                              symbol: symbol, kind: .website, action: .website(url)))
        }
        return items
    }()

    /// The rows to show for the current query, best match first.
    var items: [Item] {
        let catalog = scope.map { kind in Self.catalog.filter { $0.kind == kind } } ?? Self.catalog
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return catalog }

        let needle = text.lowercased()
        let starts = catalog.filter { $0.title.lowercased().hasPrefix(needle) }
        let contains = catalog.filter { item in
            !item.title.lowercased().hasPrefix(needle)
                && (item.title.lowercased().contains(needle) || item.subtitle.lowercased().contains(needle)
                    || item.kind.rawValue.lowercased().hasPrefix(needle))
        }

        var typed: [Item] = []
        if scope == nil, let url = URLInput.resolve(text, searchTemplate: searchTemplate) {
            let isSearch = url == URLInput.search(text, template: searchTemplate)
            typed.append(Item(
                id: "typed",
                title: isSearch ? "Search for “\(text)”" : "Open \(URLInput.displayHost(for: url))",
                subtitle: isSearch ? "Opens the results as a tile" : url.absoluteString,
                symbol: isSearch ? "magnifyingglass" : "globe",
                kind: isSearch ? .search : .website,
                action: .website(url)
            ))
        }
        // Something that starts with what was typed ("cal" for Calendar)
        // beats searching the web for it.
        return starts + typed + contains
    }

    func moveSelection(by delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    func activateSelection() {
        let current = items
        guard current.indices.contains(selection) else { return }
        activate(current[selection])
    }

    func activate(_ item: Item) {
        switch item.action {
        case .website(let url): onWebsite(url)
        case .widget(let widget): onWidget(widget)
        case .chooseFile: onChooseFile()
        case .template(let id):
            if let template = BoardTemplate.all.first(where: { $0.id == id }) { onTemplate(template) }
        }
    }
}

/// The "add something" palette: type an address or pick from the list.
struct LauncherView: View {
    static let cardWidth: CGFloat = 620
    static let maxHeight: CGFloat = 470
    /// Clear space around the card so its shadow is not cut off.
    static let margin: CGFloat = 44

    @ObservedObject var model: LauncherModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        let items = model.items
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(model.scope == .template ? "Choose a template" : "Add a website, a widget or a file", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19))
                    .focused($isFieldFocused)
                KeyCap("esc")
            }
            .padding(.horizontal, 18)
            .frame(height: 58)

            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if model.query.isEmpty, model.scope == nil, index == 0 || items[index - 1].kind != item.kind {
                                SectionLabel(item.kind.rawValue + "s")
                                    .padding(.horizontal, 10)
                                    .padding(.top, index == 0 ? 4 : 12)
                                    .padding(.bottom, 4)
                            }
                            LauncherRow(item: item, isSelected: index == model.selection)
                                .id(item.id)
                                .onTapGesture { model.activate(item) }
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.never)
                .onChange(of: model.selection) { _, selection in
                    if items.indices.contains(selection) {
                        proxy.scrollTo(items[selection].id)
                    }
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)

            HStack(spacing: 6) {
                KeyCap("↑")
                KeyCap("↓")
                Text("to choose")
                KeyCap("↩")
                Text("to add")
                Spacer()
                BrandMark(size: 11)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .frame(height: 36)
        }
        .frame(width: Self.cardWidth)
        .frame(maxHeight: Self.maxHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
        .padding(Self.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            // Focus has to wait until the view is in the window.
            DispatchQueue.main.async { isFieldFocused = true }
        }
    }
}

private struct LauncherRow: View {
    let item: LauncherModel.Item
    let isSelected: Bool

    private var tint: Color {
        switch item.kind {
        case .widget: return .blinkAccent
        case .file: return Color(red: 0.45, green: 0.85, blue: 0.7)
        case .template: return Color(red: 0.78, green: 0.66, blue: 1.0)
        case .website: return .blinkCool
        case .search: return Color.white.opacity(0.7)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .medium))
                Text(item.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if isSelected {
                KeyCap("↩")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(
            Color.white.opacity(isSelected ? 0.11 : 0),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .contentShape(Rectangle())
    }
}
