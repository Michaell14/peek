import XCTest
@testable import BlinkCore

final class URLInputTests: XCTestCase {
    private func resolve(_ text: String) -> String? {
        URLInput.resolve(text)?.absoluteString
    }

    func testFullURLsPassThrough() {
        XCTAssertEqual(resolve("https://example.com/a?b=1#c"), "https://example.com/a?b=1#c")
        XCTAssertEqual(resolve("  HTTP://Example.com  "), "HTTP://Example.com")
        XCTAssertEqual(resolve("file:///tmp/a.html"), "file:///tmp/a.html")
    }

    func testBareHostsGetHTTPS() {
        XCTAssertEqual(resolve("example.com"), "https://example.com")
        XCTAssertEqual(resolve("github.com/apple/swift"), "https://github.com/apple/swift")
        XCTAssertEqual(resolve("sub.domain.co.uk/path?q=1"), "https://sub.domain.co.uk/path?q=1")
    }

    func testLocalAddressesGetHTTP() {
        XCTAssertEqual(resolve("localhost:3000"), "http://localhost:3000")
        XCTAssertEqual(resolve("localhost"), "http://localhost")
        XCTAssertEqual(resolve("192.168.1.10:8080/admin"), "http://192.168.1.10:8080/admin")
        XCTAssertEqual(resolve("nas.local"), "http://nas.local")
    }

    func testEverythingElseIsASearch() {
        XCTAssertEqual(resolve("swift concurrency"), "https://duckduckgo.com/?q=swift%20concurrency")
        XCTAssertEqual(resolve("what.is this"), "https://duckduckgo.com/?q=what.is%20this")
        XCTAssertEqual(resolve("3.14"), "https://duckduckgo.com/?q=3.14")
        XCTAssertEqual(resolve("hello"), "https://duckduckgo.com/?q=hello")
        XCTAssertEqual(resolve("c++ & rust?"), "https://duckduckgo.com/?q=c%2B%2B%20%26%20rust%3F")
        XCTAssertEqual(resolve("999.999.999.999"), "https://duckduckgo.com/?q=999.999.999.999")
    }

    func testEmptyInput() {
        XCTAssertNil(resolve(""))
        XCTAssertNil(resolve("   \n"))
    }

    func testFilePaths() {
        XCTAssertEqual(URLInput.resolve("/tmp/report.html")?.isFileURL, true)
        XCTAssertEqual(URLInput.resolve("/tmp/report.html")?.path, "/tmp/report.html")
    }

    func testCustomSearchTemplate() {
        XCTAssertEqual(
            URLInput.resolve("cats", searchTemplate: "https://www.google.com/search?q=%s")?.absoluteString,
            "https://www.google.com/search?q=cats"
        )
    }

    func testDisplayHost() {
        XCTAssertEqual(URLInput.displayHost(for: URL(string: "https://www.example.com/x")!), "example.com")
        XCTAssertEqual(URLInput.displayHost(for: URL(string: "https://news.ycombinator.com")!), "news.ycombinator.com")
        XCTAssertEqual(URLInput.displayHost(for: URL(fileURLWithPath: "/tmp/report.pdf")), "report.pdf")
    }
}

final class RefreshPolicyTests: XCTestCase {
    func testDueOnlyAfterTheInterval() {
        let loaded = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(RefreshPolicy.isDue(lastLoaded: loaded, interval: 60, now: loaded.addingTimeInterval(59), isInUse: false))
        XCTAssertTrue(RefreshPolicy.isDue(lastLoaded: loaded, interval: 60, now: loaded.addingTimeInterval(60), isInUse: false))
    }

    func testNeverWhileOffOrInUse() {
        let loaded = Date(timeIntervalSince1970: 1000)
        let later = loaded.addingTimeInterval(100_000)
        XCTAssertFalse(RefreshPolicy.isDue(lastLoaded: loaded, interval: 0, now: later, isInUse: false))
        XCTAssertFalse(RefreshPolicy.isDue(lastLoaded: loaded, interval: 60, now: later, isInUse: true))
    }

    func testLabels() {
        XCTAssertEqual(RefreshPolicy.presets.map(RefreshPolicy.label), [
            "Off", "30 seconds", "1 minute", "5 minutes", "15 minutes", "30 minutes", "1 hour",
        ])
        XCTAssertEqual(RefreshPolicy.label(for: 7200), "2 hours")
    }
}

final class EventLayoutTests: XCTestCase {
    func testSeparateEventsUseTheFullWidth() {
        let slots = EventLayout.arrange([(9, 10), (10, 11), (13, 14)])
        XCTAssertEqual(slots, Array(repeating: EventLayout.Slot(column: 0, columnCount: 1), count: 3))
    }

    func testOverlappingEventsSitSideBySide() {
        let slots = EventLayout.arrange([(9, 11), (10, 12)])
        XCTAssertEqual(slots[0], EventLayout.Slot(column: 0, columnCount: 2))
        XCTAssertEqual(slots[1], EventLayout.Slot(column: 1, columnCount: 2))
    }

    func testColumnsAreReusedWithinACluster() {
        // A: 9-12, B: 9-10, C: 10-11 (fits under B), D: 14-15 (new cluster).
        let slots = EventLayout.arrange([(9, 12), (9, 10), (10, 11), (14, 15)])
        XCTAssertEqual(slots[0], EventLayout.Slot(column: 1, columnCount: 2))
        XCTAssertEqual(slots[1], EventLayout.Slot(column: 0, columnCount: 2))
        XCTAssertEqual(slots[2], EventLayout.Slot(column: 0, columnCount: 2))
        XCTAssertEqual(slots[3], EventLayout.Slot(column: 0, columnCount: 1))
    }

    func testResultFollowsInputOrder() {
        let slots = EventLayout.arrange([(15, 16), (9, 11), (10, 12)])
        XCTAssertEqual(slots[0].columnCount, 1)
        XCTAssertEqual(slots[1].column, 0)
        XCTAssertEqual(slots[2].column, 1)
    }

    func testOverlappingEventsNeverShareAColumn() {
        var generator = SeededGenerator(seed: 7)
        for _ in 0..<100 {
            let intervals: [(start: Double, end: Double)] = (0..<12).map { _ in
                let start = Double.random(in: 0...20, using: &generator)
                return (start, start + Double.random(in: 0.25...4, using: &generator))
            }
            let slots = EventLayout.arrange(intervals)
            for i in intervals.indices {
                XCTAssertLessThan(slots[i].column, slots[i].columnCount)
                for j in intervals.indices where j > i {
                    let overlap = intervals[i].start < intervals[j].end && intervals[j].start < intervals[i].end
                    if overlap {
                        XCTAssertNotEqual(slots[i].column, slots[j].column)
                    }
                }
            }
        }
    }

    func testEmpty() {
        XCTAssertTrue(EventLayout.arrange([]).isEmpty)
    }
}

final class WorldClockTests: XCTestCase {
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    /// 15 January 2026, 20:30 in New York (01:30 UTC on the 16th).
    private let evening = Date(timeIntervalSince1970: 1_768_527_000)

    func testCityNames() {
        XCTAssertEqual(WorldClock.cityName(for: "America/New_York"), "New York")
        XCTAssertEqual(WorldClock.cityName(for: "America/Argentina/Buenos_Aires"), "Buenos Aires")
        XCTAssertEqual(WorldClock.cityName(for: "UTC"), "UTC")
    }

    func testOffsetDescriptions() {
        XCTAssertEqual(WorldClock.offsetDescription(for: tokyo, relativeTo: newYork, at: evening), "Tomorrow, +14 hrs")
        XCTAssertEqual(WorldClock.offsetDescription(for: kolkata, relativeTo: newYork, at: evening), "Tomorrow, +10:30 hrs")
        XCTAssertEqual(WorldClock.offsetDescription(for: losAngeles, relativeTo: newYork, at: evening), "Today, −3 hrs")
        XCTAssertEqual(WorldClock.offsetDescription(for: newYork, relativeTo: newYork, at: evening), "Today")
        XCTAssertEqual(WorldClock.offsetDescription(for: newYork, relativeTo: tokyo, at: evening), "Yesterday, −14 hrs")
    }

    func testSingularHour() {
        let chicago = TimeZone(identifier: "America/Chicago")!
        XCTAssertEqual(WorldClock.offsetDescription(for: chicago, relativeTo: newYork, at: evening), "Today, −1 hr")
    }

    func testRows() throws {
        let remote = try XCTUnwrap(WorldClock.row(identifier: "Asia/Tokyo", at: evening, local: newYork, uses24Hour: false))
        XCTAssertEqual(remote.city, "Tokyo")
        XCTAssertEqual(remote.time, "10:30")
        XCTAssertEqual(remote.period, "AM")
        XCTAssertEqual(remote.detail, "Tomorrow, +14 hrs")
        XCTAssertTrue(remote.isDaytime, "10:30 in the morning")

        let local = try XCTUnwrap(WorldClock.row(identifier: ClockConfig.localZone, at: evening, local: newYork, uses24Hour: true))
        XCTAssertEqual(local.city, "Local")
        XCTAssertEqual(local.detail, "New York")
        XCTAssertEqual(local.time, "20:30")
        XCTAssertEqual(local.period, "")
        XCTAssertFalse(local.isDaytime, "half past eight at night")

        XCTAssertNil(WorldClock.row(identifier: "Nowhere/Atlantis", at: evening, local: newYork, uses24Hour: true))
    }
}
