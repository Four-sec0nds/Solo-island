import XCTest
@testable import IslandCore

final class NotchActivityTests: XCTestCase {
    func testNoTrackOrFocusHidesTheWings() {
        var track = NowPlaying(); track.playing = true
        XCTAssertEqual(NotchActivity(track: track, focus: nil), .hidden)
        XCTAssertFalse(NotchActivity(track: track, focus: nil).isVisible)
    }

    func testPausedTrackKeepsItsCoverWithoutClaimingPlayback() {
        var track = NowPlaying(); track.title = "Track"; track.playing = true
        XCTAssertEqual(NotchActivity(track: track, focus: nil), .music(.playing))
        track.playing = false
        XCTAssertEqual(NotchActivity(track: track, focus: nil), .music(.paused))
        track.title = nil
        XCTAssertEqual(NotchActivity(track: track, focus: nil), .hidden)
    }

    func testFocusOwnsTimeWhileRetainingMusicStateAndResumesMusicOnCompletion() {
        let start = Date(timeIntervalSince1970: 1000)
        var track = NowPlaying(); track.title = "Track"; track.playing = true
        var focus = FocusSession(taskID: UUID(), minutes: 25, now: start)
        XCTAssertEqual(NotchActivity(track: track, focus: focus), .focus(paused: false, music: .playing))
        focus.pause(at: start.addingTimeInterval(60))
        XCTAssertEqual(NotchActivity(track: track, focus: focus), .focus(paused: true, music: .playing))
        track.playing = false
        XCTAssertEqual(NotchActivity(track: track, focus: focus), .focus(paused: true, music: .paused))
        XCTAssertEqual(NotchActivity(track: track, focus: nil), .music(.paused))
        XCTAssertEqual(NotchActivity(track: NowPlaying(), focus: focus), .focus(paused: true, music: nil))
    }

    func testPlaybackMotionIsBoundedAndFreezesForPauseOrReducedMotion() {
        for time in [0, 1, 78.5, Double.infinity, Double.nan] {
            let levels = PlaybackIndicator.levels(position: time, identity: "Artist/Track", moving: true)
            XCTAssertEqual(levels.count, 3)
            XCTAssertTrue(levels.allSatisfy { $0.isFinite && (0.25...1).contains($0) })
        }
        XCTAssertNotEqual(PlaybackIndicator.levels(position: 0, identity: "Track", moving: true),
                          PlaybackIndicator.levels(position: 1, identity: "Track", moving: true))
        XCTAssertEqual(PlaybackIndicator.levels(position: 0, identity: "First", moving: false),
                       PlaybackIndicator.levels(position: 10, identity: "Second", moving: false))
    }
}
