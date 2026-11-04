import XCTest
@testable import IslandCore

final class CompactPlaybackTests: XCTestCase {
    func testOldSavedPanelShrinksOnceAndThenKeepsTheUsersNewWidth() throws {
        var settings = try JSONDecoder().decode(IslandSettings.self, from: Data(#"{"expandedWidth":820,"accent":"purple","focusMinutes":45}"#.utf8))
        settings.adoptCompactLayout()
        XCTAssertEqual(settings.expandedWidth, 560)
        XCTAssertEqual(settings.accent, "purple"); XCTAssertEqual(settings.focusMinutes, 45)
        settings.expandedWidth = 610
        var restored = try JSONDecoder().decode(IslandSettings.self, from: JSONEncoder().encode(settings))
        restored.adoptCompactLayout()
        XCTAssertEqual(restored.expandedWidth, 610)
        XCTAssertEqual(restored.compactLayoutRevision, IslandLayout.revision)
        XCTAssertEqual(IslandLayout.width(.nan), 560)
        XCTAssertEqual(IslandLayout.width(300), 520)
        XCTAssertEqual(IslandLayout.width(900), 680)
    }
    func testMissingPositionDoesNotRemoveAbsoluteSeeking() {
        var track = NowPlaying(); track.title = "Трек"; track.duration = 240
        XCTAssertNil(track.elapsedTime)
        XCTAssertTrue(track.canSeek)
        for duration in [Double.zero, -1, .infinity, .nan] {
            track.duration = duration; XCTAssertFalse(track.canSeek)
        }
        track.duration = nil; XCTAssertFalse(track.canSeek)
    }
}
