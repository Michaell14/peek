import XCTest
@testable import BlinkCore

final class NewWindowPolicyTests: XCTestCase {
    func testAPageOpeningAWindowWhileInUseGetsAPopup() {
        // "Sign in with Google": the page's script calls window.open.
        XCTAssertEqual(NewWindowPolicy.choice(isLinkClick: false, isInUse: true), .popup)
    }

    func testANewTabLinkOpensInTheTile() {
        XCTAssertEqual(NewWindowPolicy.choice(isLinkClick: true, isInUse: true), .sameTile)
    }

    func testNothingOpensWhileTheOverlayIsOnlyGlancedAtOrHidden() {
        XCTAssertEqual(NewWindowPolicy.choice(isLinkClick: false, isInUse: false), .ignore)
        XCTAssertEqual(NewWindowPolicy.choice(isLinkClick: true, isInUse: false), .ignore)
    }
}

final class PopupSizingTests: XCTestCase {
    private func size(_ width: Double?, _ height: Double?, screen: (Double, Double) = (1440, 900)) -> [Double] {
        let result = PopupSizing.size(requestedWidth: width, requestedHeight: height, screenWidth: screen.0, screenHeight: screen.1)
        return [result.width, result.height]
    }

    func testTheRequestedSizeIsUsed() {
        XCTAssertEqual(size(500, 600), [500, 600])
    }

    func testWithoutASizeItIsSignInSized() {
        XCTAssertEqual(size(nil, nil), [480, 640])
        XCTAssertEqual(size(0, -5), [480, 640])
        XCTAssertEqual(size(.nan, .infinity), [480, 640])
    }

    func testTinyRequestsAreMadeUsable() {
        XCTAssertEqual(size(100, 50), [360, 420])
    }

    func testItAlwaysFitsOnTheScreenWithRoomAround() {
        XCTAssertEqual(size(4000, 3000), [1360, 820])
        XCTAssertEqual(size(nil, nil, screen: (1024, 600)), [480, 520])
    }

    func testAVerySmallScreenStillGetsTheMinimum() {
        XCTAssertEqual(size(nil, nil, screen: (300, 300)), [360, 420])
    }
}
