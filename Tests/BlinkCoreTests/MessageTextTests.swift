import XCTest
@testable import BlinkCore

final class MessageTextTests: XCTestCase {
    /// The start of an archived attributed string as Messages saves it, with
    /// `text` where the string goes.
    private func archive(_ text: String, longLength: Bool = false) -> [UInt8] {
        let utf8 = Array(text.utf8)
        var bytes: [UInt8] = [0x04, 0x0B] + Array("streamtyped".utf8) + [0x81, 0xE8, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84]
        bytes += [0x12] + Array("NSAttributedString".utf8) + [0x00, 0x84, 0x84]
        bytes += [0x08] + Array("NSObject".utf8) + [0x00, 0x85, 0x92, 0x84, 0x84, 0x84]
        bytes += [0x08] + Array("NSString".utf8) + [0x01, 0x94, 0x84, 0x01, 0x2B]
        if longLength || utf8.count >= 0x80 {
            bytes += [0x81, UInt8(utf8.count & 0xFF), UInt8(utf8.count >> 8)]
        } else {
            bytes += [UInt8(utf8.count)]
        }
        bytes += utf8
        bytes += [0x86, 0x84, 0x02, 0x69, 0x49, 0x01, 0x0B, 0x92, 0x84, 0x84, 0x84]
        return bytes
    }

    func testReadsTextFromAnArchivedMessage() {
        XCTAssertEqual(MessageText.fromAttributedBody(archive("Can we move the review to 3?")), "Can we move the review to 3?")
        XCTAssertEqual(MessageText.fromAttributedBody(archive("Ça va? 👋")), "Ça va? 👋")
    }

    func testReadsALongMessage() {
        let long = String(repeating: "The new build is up. ", count: 20)
        XCTAssertEqual(MessageText.fromAttributedBody(archive(long)), long)
    }

    func testRefusesWhatIsNotAnArchivedString() {
        XCTAssertNil(MessageText.fromAttributedBody([]))
        XCTAssertNil(MessageText.fromAttributedBody(Array("hello".utf8)))
        // A length that runs past the end.
        var cut = archive("Lunch on Thursday?")
        cut.removeLast(20)
        XCTAssertNil(MessageText.fromAttributedBody(cut))
    }

    func testDisplayPrefersTheTextColumnAndDropsAttachmentMarks() {
        XCTAssertEqual(MessageText.display(text: "Hi", attributedBody: archive("Other")), "Hi")
        XCTAssertEqual(MessageText.display(text: nil, attributedBody: archive("From the archive")), "From the archive")
        XCTAssertEqual(MessageText.display(text: "\u{FFFC}", attributedBody: []), "Attachment")
        XCTAssertEqual(MessageText.display(text: "\u{FFFC}Look at this", attributedBody: []), "Look at this")
    }

    func testMessagesTimeInNanosecondsAndSeconds() {
        let date = Date(timeIntervalSinceReferenceDate: 784_000_000)
        XCTAssertEqual(MessageText.date(fromMessagesTime: 784_000_000_000_000_000), date)
        XCTAssertEqual(MessageText.date(fromMessagesTime: 784_000_000), date, "older Macs saved seconds")
        XCTAssertEqual(MessageText.date(fromMessagesTime: MessageText.messagesTime(from: date)), date)
    }

    func testInitials() {
        XCTAssertEqual(MessageText.initials(for: "Maya Chen"), "MC")
        XCTAssertEqual(MessageText.initials(for: "Design team"), "DT")
        XCTAssertEqual(MessageText.initials(for: "Dad"), "D")
        XCTAssertEqual(MessageText.initials(for: "Anne-Marie Lopez Rivera"), "AM")
        XCTAssertEqual(MessageText.initials(for: "+1 (555) 010-2233"), "")
        XCTAssertEqual(MessageText.initials(for: "sam@example.com"), "")
    }

    func testShortTimes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        // Thursday 13 November 2025, 15:00 UTC.
        let now = Date(timeIntervalSince1970: 1_763_046_000)
        func short(_ secondsAgo: Double) -> String {
            MessageText.shortTime(now.addingTimeInterval(-secondsAgo), now: now, calendar: calendar, locale: locale)
        }
        XCTAssertEqual(short(20), "now")
        XCTAssertEqual(short(4 * 60), "4m")
        XCTAssertEqual(short(3 * 3600 + 60), "3h")
        XCTAssertEqual(short(20 * 3600), "Yesterday")
        XCTAssertEqual(short(3 * 86_400), "Mon")
        XCTAssertEqual(short(30 * 86_400), "Oct 14")
    }

    func testPhoneKeysMatchHoweverTheNumberIsWritten() {
        XCTAssertEqual(MessageText.phoneKey("+1 (555) 010-2233"), MessageText.phoneKey("5550102233"))
        XCTAssertEqual(MessageText.phoneKey("+44 20 7946 0958"), MessageText.phoneKey("020 7946 0958").map { String($0.suffix(10)) })
        XCTAssertNil(MessageText.phoneKey("sam@example.com"))
        XCTAssertNil(MessageText.phoneKey("12"))
    }

    func testGroupTitles() {
        XCTAssertEqual(MessageText.groupTitle([]), "Group")
        XCTAssertEqual(MessageText.groupTitle(["Maya Chen", "Leo Park"]), "Maya and Leo")
        XCTAssertEqual(MessageText.groupTitle(["Maya Chen", "Leo Park", "+1 555 010 2233"]), "Maya, Leo and +1 555 010 2233")
        XCTAssertEqual(MessageText.groupTitle(["A", "B", "C", "D", "E"]), "A, B and 3 others")
    }

    func testMessagesWidgetsAreSavedAndRead() throws {
        let tile = Tile(content: .widget(.messages(MessagesConfig())))
        let decoded = try JSONDecoder().decode(Tile.self, from: JSONEncoder().encode(tile))
        XCTAssertEqual(decoded, tile)
        XCTAssertNil(tile.flowHeight, "Messages fills its column")
    }
}
