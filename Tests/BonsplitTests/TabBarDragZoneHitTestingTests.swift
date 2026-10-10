import AppKit
import XCTest
@testable import Bonsplit

final class TabBarDragZoneHitTestingTests: XCTestCase {
    func testLeadingChromeDoesNotCaptureWhileTabFramesAreTemporarilyMissing() {
        let bounds = CGRect(x: 0, y: 0, width: 80, height: 28)

        XCTAssertFalse(
            TabBarDragZoneHitTesting.shouldCaptureLeadingChrome(
                at: CGPoint(x: 24, y: 14),
                bounds: bounds,
                tabFrames: [],
                hasTabs: true
            ),
            "A visible tab must not be swallowed by the titlebar drag lane while geometry is catching up."
        )
    }

    func testTrailingChromeStillCapturesAfterKnownTabFrames() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 28)
        let tabFrame = CGRect(x: 8, y: 0, width: 72, height: 28)

        XCTAssertTrue(
            TabBarDragZoneHitTesting.shouldCaptureTrailingEmptyChrome(
                at: CGPoint(x: 180, y: 14),
                bounds: bounds,
                tabFrames: [tabFrame],
                reservedTrailingWidth: 0
            )
        )
        XCTAssertFalse(
            TabBarDragZoneHitTesting.shouldCaptureTrailingEmptyChrome(
                at: CGPoint(x: 40, y: 14),
                bounds: bounds,
                tabFrames: [tabFrame],
                reservedTrailingWidth: 0
            )
        )
    }
}
