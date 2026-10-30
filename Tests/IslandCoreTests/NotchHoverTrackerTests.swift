import XCTest
@testable import IslandCore

final class NotchHoverTrackerTests: XCTestCase {
    func testNormalHoverKeepsItsDelayAndIgnoresRepeatedSamples() {
        var tracker = NotchHoverTracker()
        XCTAssertNil(tracker.update(isInside: false))
        XCTAssertEqual(tracker.update(isInside: true), .entered(immediately: false))
        XCTAssertNil(tracker.update(isInside: true))
        XCTAssertEqual(tracker.update(isInside: false), .exited)
        XCTAssertEqual(tracker.update(isInside: true), .entered(immediately: false))
    }

    func testSpaceSwitchReevaluatesAStationaryCursorAlreadyInside() {
        var tracker = NotchHoverTracker()
        _ = tracker.update(isInside: true)
        tracker.screenDidChange()
        XCTAssertEqual(tracker.update(isInside: true), .entered(immediately: true))
        XCTAssertNil(tracker.update(isInside: true))
    }

    func testOutsideSamplesAfterSwitchPreserveImmediateFirstEntry() {
        var tracker = NotchHoverTracker()
        tracker.screenDidChange()
        XCTAssertEqual(tracker.update(isInside: false), .exited)
        XCTAssertNil(tracker.update(isInside: false))
        XCTAssertEqual(tracker.update(isInside: true), .entered(immediately: true))
        XCTAssertEqual(tracker.update(isInside: false), .exited)
        XCTAssertEqual(tracker.update(isInside: true), .entered(immediately: false))
    }

    func testRepeatedDisplayChangesDoNotLoseTheNextEntry() {
        var tracker = NotchHoverTracker()
        tracker.screenDidChange()
        _ = tracker.update(isInside: false)
        tracker.screenDidChange()
        XCTAssertEqual(tracker.update(isInside: true), .entered(immediately: true))
        tracker.screenDidChange()
        XCTAssertEqual(tracker.update(isInside: true), .entered(immediately: true))
    }
}
