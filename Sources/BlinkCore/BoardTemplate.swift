import Foundation

/// A ready-made board: a few tiles, already in columns and sized, for the
/// way a lot of people work. Choosing one fills a board; everything in it
/// can be moved, resized or removed afterwards like any tile.
public struct BoardTemplate: Identifiable, Hashable, Sendable {
    /// One tile in the template, with its place in its column.
    public struct Slot: Hashable, Sendable {
        public var content: TileContent
        public var width: Double
        /// nil fills what is left of the column.
        public var height: Double?

        public init(_ content: TileContent, width: Double, height: Double? = nil) {
            self.content = content
            self.width = width
            self.height = height
        }
    }

    public var id: String
    public var name: String
    public var summary: String
    /// An SF Symbol for the template.
    public var symbol: String
    /// Left to right; each column top to bottom.
    public var columns: [[Slot]]

    /// Fresh tiles for a board, stacked in their columns.
    public func makeTiles() -> [Tile] {
        columns.flatMap { column -> [Tile] in
            let columnID = UUID()
            return column.map { slot in
                var tile = Tile(content: slot.content)
                tile.column = columnID
                tile.flowWidth = slot.width
                tile.flowHeight = slot.height
                return tile
            }
        }
    }

    /// The template as the layout sees it, for drawing a small map of it.
    public var flowItems: [FlowLayout.Item] {
        makeTiles().map(\.flowItem)
    }
}

extension BoardTemplate {
    private static func site(_ address: String, refreshEvery minutes: Double = 0) -> TileContent {
        var web = WebContent(url: URL(string: address) ?? URL(fileURLWithPath: "/"))
        web.refreshInterval = minutes * 60
        return .web(web)
    }

    private static let calendarDay = TileContent.widget(.calendar(CalendarConfig(mode: .day)))
    private static let calendarWeek = TileContent.widget(.calendar(CalendarConfig(mode: .agenda)))
    private static let messages = TileContent.widget(.messages(MessagesConfig()))
    private static let notes = TileContent.widget(.notes(NotesConfig()))
    private static let reminders = TileContent.widget(.reminders(RemindersConfig(filter: .today)))

    private static func clock(_ zones: [String]) -> TileContent {
        .widget(.clock(ClockConfig(zones: [ClockConfig.localZone] + zones)))
    }

    /// A clock as tall as its cities need, as when it is added by hand.
    private static func clockSlot(_ zones: [String], width: Double) -> Slot {
        let content = clock(zones)
        return Slot(content, width: width, height: Tile.defaultSizing(for: content).height)
    }

    /// Every template, in the order they are offered.
    public static let all: [BoardTemplate] = [
        BoardTemplate(
            id: "day",
            name: "My Day",
            summary: "Calendar on the left, Messages in the middle, reminders and a note on the right",
            symbol: "sun.max",
            columns: [
                [Slot(calendarDay, width: 300)],
                [Slot(messages, width: 380)],
                [Slot(reminders, width: 300, height: 380), Slot(notes, width: 300)],
            ]
        ),
        BoardTemplate(
            id: "inbox",
            name: "Inbox",
            summary: "Messages, your email in the middle, and the week ahead",
            symbol: "tray",
            columns: [
                [Slot(messages, width: 330)],
                [Slot(site("https://mail.google.com"), width: 560)],
                [Slot(calendarWeek, width: 300)],
            ]
        ),
        BoardTemplate(
            id: "engineering",
            name: "Engineering",
            summary: "Pull requests, the time where your team is, today's meetings and a scratchpad",
            symbol: "chevron.left.forwardslash.chevron.right",
            columns: [
                [Slot(site("https://github.com/pulls", refreshEvery: 5), width: 540)],
                [clockSlot(["America/New_York", "Europe/London"], width: 290),
                 Slot(calendarDay, width: 290)],
                [Slot(reminders, width: 290, height: 360), Slot(notes, width: 290)],
            ]
        ),
        BoardTemplate(
            id: "team",
            name: "Remote Team",
            summary: "Where everyone is and what time it is there, the week ahead and your conversations",
            symbol: "globe.americas",
            columns: [
                [clockSlot(["America/Los_Angeles", "America/New_York", "Europe/London", "Asia/Tokyo"], width: 300),
                 Slot(notes, width: 300)],
                [Slot(calendarWeek, width: 320)],
                [Slot(messages, width: 360)],
            ]
        ),
        BoardTemplate(
            id: "markets",
            name: "Markets",
            summary: "The markets, the news, and the time in New York, London and Tokyo",
            symbol: "chart.line.uptrend.xyaxis",
            columns: [
                [clockSlot(["America/New_York", "Europe/London", "Asia/Tokyo"], width: 290),
                 Slot(notes, width: 290)],
                [Slot(site("https://www.google.com/finance", refreshEvery: 5), width: 520)],
                [Slot(site("https://news.ycombinator.com", refreshEvery: 15), width: 420)],
            ]
        ),
        BoardTemplate(
            id: "study",
            name: "Study",
            summary: "A reference on the left, a big note for writing, and what is due",
            symbol: "book",
            columns: [
                [Slot(site("https://en.wikipedia.org"), width: 480)],
                [Slot(notes, width: 440)],
                [Slot(reminders, width: 300, height: 400), Slot(calendarDay, width: 300)],
            ]
        ),
    ]
}

extension Workspace {
    /// Fills a board with a template's tiles, in place of what was there.
    public mutating func applyTemplate(_ template: BoardTemplate, to boardID: UUID) {
        updateBoard(boardID) { board in
            board.tiles = template.makeTiles()
        }
    }
}
