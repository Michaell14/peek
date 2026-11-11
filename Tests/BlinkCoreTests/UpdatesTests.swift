import XCTest
@testable import BlinkCore

final class UpdatesTests: XCTestCase {
    private let source = UpdateSource(repository: "Michaell14/peek")

    private func version(_ text: String) -> AppVersion {
        guard let version = AppVersion(text) else {
            XCTFail("\(text) should be a version")
            return AppVersion("0")!
        }
        return version
    }

    // MARK: - Versions

    func testVersionsCompareNumberByNumber() {
        XCTAssertLessThan(version("0.9.0"), version("0.10.0"), "ten is more than nine")
        XCTAssertLessThan(version("0.1.9"), version("0.2"))
        XCTAssertLessThan(version("1.9.9"), version("2.0.0"))
        XCTAssertGreaterThan(version("1.0.1"), version("1.0"))
        XCTAssertFalse(version("1.2.0") < version("1.2.0"))
    }

    func testTrailingZerosAndPrefixesDoNotMatter() {
        XCTAssertEqual(version("1.2"), version("1.2.0"))
        XCTAssertEqual(version("v1.2.0"), version("1.2"))
        XCTAssertEqual(version(" 0.3.1\n"), version("0.3.1"))
        XCTAssertEqual(version("1.4.1-beta.2"), version("1.4.1"), "anything after the numbers is ignored")
        XCTAssertEqual(Set([version("2"), version("2.0"), version("2.0.0")]).count, 1)
    }

    func testVersionsPrintInFull() {
        XCTAssertEqual(version("0.2.0").description, "0.2")
        XCTAssertEqual(version("3").description, "3.0")
        XCTAssertEqual(version("v1.10.4").description, "1.10.4")
    }

    func testWhatIsNotAVersion() {
        for text in ["", "v", "latest", "beta-1", "1..2", ".5", "1.2.", "1.2.3.4.5", "99999999999999999999"] {
            XCTAssertNil(AppVersion(text), "\"\(text)\" should not be read as a version")
        }
    }

    // MARK: - Reading a release

    private let published = """
    {
      "tag_name": "v0.3.0",
      "name": "Blink 0.3.0",
      "body": "  Faster to open.\\n",
      "html_url": "https://github.com/Michaell14/peek/releases/tag/v0.3.0",
      "draft": false,
      "prerelease": false,
      "unknown_field": {"nested": [1, 2, 3]},
      "assets": [
        {"name": "Blink.dmg", "size": 4100000, "browser_download_url": "https://github.com/Michaell14/peek/releases/download/v0.3.0/Blink.dmg"},
        {"name": "broken"},
        {"name": "Blink.zip", "size": 3900000, "browser_download_url": "https://github.com/Michaell14/peek/releases/download/v0.3.0/Blink.zip"}
      ]
    }
    """

    private func decode(_ json: String) throws -> ReleaseInfo {
        try JSONDecoder().decode(ReleaseInfo.self, from: Data(json.utf8))
    }

    func testReadsAReleaseAsGitHubDescribesIt() throws {
        let release = try decode(published)
        XCTAssertEqual(release.tag, "v0.3.0")
        XCTAssertEqual(release.assets.map(\.name), ["Blink.dmg", "Blink.zip"], "the asset with no address is skipped")
        XCTAssertEqual(release.assets.last?.size, 3_900_000)
        XCTAssertFalse(release.isDraft)
    }

    func testAReleaseWithOnlyATagStillReads() throws {
        let release = try decode(#"{"tag_name": "v1.0"}"#)
        XCTAssertEqual(release.notes, "")
        XCTAssertNil(release.page)
        XCTAssertTrue(release.assets.isEmpty)
        XCTAssertThrowsError(try decode(#"{"name": "no tag"}"#))
        XCTAssertThrowsError(try decode(#"{"message": "Not Found"}"#), "GitHub's answer when there are no releases")
    }

    // MARK: - Deciding what to offer

    func testOffersANewerRelease() throws {
        let offer = try XCTUnwrap(UpdateCheck.offer(from: decode(published), current: version("0.2.0"), source: source))
        XCTAssertEqual(offer.version, version("0.3"))
        XCTAssertEqual(offer.versionText, "0.3.0")
        XCTAssertEqual(offer.notes, "Faster to open.")
        XCTAssertEqual(offer.archive?.lastPathComponent, "Blink.zip")
        XCTAssertEqual(offer.archiveSize, 3_900_000)
        XCTAssertEqual(offer.page?.host, "github.com")
    }

    func testOffersNothingWhenAlreadyCurrentOrAhead() throws {
        let release = try decode(published)
        XCTAssertNil(UpdateCheck.offer(from: release, current: version("0.3.0"), source: source))
        XCTAssertNil(UpdateCheck.offer(from: release, current: version("0.3"), source: source))
        XCTAssertNil(UpdateCheck.offer(from: release, current: version("1.0"), source: source))
    }

    func testDraftsPrereleasesAndOddTagsAreNotOffered() {
        let old = version("0.1")
        XCTAssertNil(UpdateCheck.offer(from: ReleaseInfo(tag: "v9.0", isDraft: true), current: old, source: source))
        XCTAssertNil(UpdateCheck.offer(from: ReleaseInfo(tag: "v9.0", isPrerelease: true), current: old, source: source))
        XCTAssertNil(UpdateCheck.offer(from: ReleaseInfo(tag: "nightly"), current: old, source: source))
    }

    func testAReleaseWithoutAnArchiveIsOfferedButCannotInstallItself() throws {
        let dmg = try XCTUnwrap(URL(string: "https://github.com/Michaell14/peek/releases/download/v2.0/Blink.dmg"))
        let release = ReleaseInfo(tag: "v2.0", assets: [.init(name: "Blink.dmg", url: dmg)])
        let offer = try XCTUnwrap(UpdateCheck.offer(from: release, current: version("1.0"), source: source))
        XCTAssertNil(offer.archive)
    }

    // MARK: - Where code may come from

    func testOnlyFetchesCodeFromItsOwnReleasesOverHTTPS() throws {
        func trusts(_ address: String) throws -> Bool {
            source.trusts(try XCTUnwrap(URL(string: address)))
        }
        XCTAssertTrue(try trusts("https://github.com/Michaell14/peek/releases/download/v0.3.0/Blink.zip"))
        XCTAssertTrue(try trusts("HTTPS://GitHub.com/Michaell14/peek/releases/download/v0.3.0/Blink.zip"))

        XCTAssertFalse(try trusts("http://github.com/Michaell14/peek/releases/download/v0.3.0/Blink.zip"), "not over plain http")
        XCTAssertFalse(try trusts("https://github.com/someone-else/peek/releases/download/v0.3.0/Blink.zip"), "another repository")
        XCTAssertFalse(try trusts("https://github.com/Michaell14/peek-evil/releases/download/v1/Blink.zip"))
        XCTAssertFalse(try trusts("https://github.com.example.org/Michaell14/peek/releases/download/v1/Blink.zip"))
        XCTAssertFalse(try trusts("https://example.org/Blink.zip"))
        XCTAssertFalse(try trusts("https://api.github.com/Blink.zip"), "the feed's own host is not enough")
        XCTAssertFalse(try trusts("file:///tmp/Blink.zip"))
    }

    func testAnArchiveFromElsewhereIsLeftOutOfTheOffer() throws {
        let elsewhere = try XCTUnwrap(URL(string: "https://example.org/Blink.zip"))
        let release = ReleaseInfo(tag: "v2.0", assets: [.init(name: "Blink.zip", url: elsewhere)])
        let offer = try XCTUnwrap(UpdateCheck.offer(from: release, current: version("1.0"), source: source))
        XCTAssertNil(offer.archive)
    }

    func testAFeedNamedOnTheCommandLineMayServeItsOwnArchive() throws {
        let feed = try XCTUnwrap(URL(string: "http://127.0.0.1:8766/release.json"))
        let local = UpdateSource(repository: "Michaell14/peek", feed: feed)
        XCTAssertFalse(local.isOfficial)
        XCTAssertTrue(source.isOfficial)
        XCTAssertEqual(source.feed.absoluteString, "https://api.github.com/repos/Michaell14/peek/releases/latest")

        XCTAssertTrue(local.trusts(try XCTUnwrap(URL(string: "http://127.0.0.1:8766/Blink.zip"))))
        XCTAssertFalse(local.trusts(try XCTUnwrap(URL(string: "http://127.0.0.1:9999/Blink.zip"))), "another port is another server")
        XCTAssertFalse(local.trusts(try XCTUnwrap(URL(string: "http://example.org:8766/Blink.zip"))))
        XCTAssertTrue(local.trusts(try XCTUnwrap(URL(string: "https://github.com/Michaell14/peek/releases/download/v1/Blink.zip"))))
    }

    // MARK: - When to ask

    func testAsksOnceADay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: nil, now: now), "never asked")
        XCTAssertFalse(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        XCTAssertFalse(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-86_399), now: now))
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-86_400), now: now))
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(3600), now: now), "the clock went backwards")
    }

    // MARK: - Checking what was downloaded

    func testWhatWasUnpackedMustBeWhatWasOffered() throws {
        let offer = try XCTUnwrap(UpdateCheck.offer(from: decode(published), current: version("0.2"), source: source))
        let ours = "org.blink-app.Blink"
        XCTAssertNil(UpdateCheck.problem(withIdentifier: ours, version: "0.3.0", expecting: offer, identifier: ours))
        XCTAssertNil(UpdateCheck.problem(withIdentifier: ours, version: "0.3", expecting: offer, identifier: ours))

        XCTAssertEqual(
            UpdateCheck.problem(withIdentifier: "com.example.Other", version: "0.3.0", expecting: offer, identifier: ours),
            .differentApp(found: "com.example.Other")
        )
        XCTAssertEqual(
            UpdateCheck.problem(withIdentifier: nil, version: "0.3.0", expecting: offer, identifier: ours),
            .differentApp(found: "nothing")
        )
        XCTAssertEqual(
            UpdateCheck.problem(withIdentifier: ours, version: "0.2.0", expecting: offer, identifier: ours),
            .differentVersion(found: "0.2.0"),
            "an archive that would take someone backwards"
        )
        XCTAssertEqual(
            UpdateCheck.problem(withIdentifier: ours, version: nil, expecting: offer, identifier: ours),
            .differentVersion(found: "nothing")
        )
    }

    // MARK: - The setting

    func testCheckingForUpdatesIsOnUnlessTurnedOff() throws {
        XCTAssertTrue(AppSettings().checksForUpdates)
        let saved = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"tapThreshold": 0.3}"#.utf8))
        XCTAssertTrue(saved.checksForUpdates, "a layout saved before the setting existed")
        let off = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"checksForUpdates": false}"#.utf8))
        XCTAssertFalse(off.checksForUpdates)
    }
}
