import XCTest
@testable import IslandCore

final class IslandCoreTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value
    }
    func testCommandRunnerDrainsBothPipesAndPreservesFailureStatus() async throws {
        let result = try await ProcessRunner.run("/bin/sh", ["-c", "head -c 131072 /dev/zero; head -c 131072 /dev/zero >&2; exit 7"])
        XCTAssertEqual(result.status, 7)
        XCTAssertEqual(result.output.count, 131072)
        XCTAssertEqual(result.error.utf8.count, 131072)
    }
    func testCommandRunnerTerminatesExpiredProcess() async throws {
        let start = Date()
        let result = try await ProcessRunner.run("/bin/sleep", ["10"], timeout: 0.1)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
    func testTaskListsIncludeOverdueAndUndatedButExcludeCompleted() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let overdue = IslandTask(title: "Просрочена", dueAt: now.addingTimeInterval(-100))
        let today = IslandTask(title: "Сегодня", dueAt: tomorrow.addingTimeInterval(-1))
        let future = IslandTask(title: "Завтра", dueAt: tomorrow)
        let undated = IslandTask(title: "Без срока")
        let completed = IslandTask(title: "Готова", dueAt: now, completedAt: now)
        let tasks = [future, completed, undated, today, overdue]
        XCTAssertEqual(TaskQuery.tasks(tasks, in: .today, now: now, calendar: calendar).map(\.id), [overdue.id, today.id, undated.id])
        XCTAssertEqual(TaskQuery.tasks(tasks, in: .upcoming, now: now, calendar: calendar).map(\.id), [future.id])
        XCTAssertEqual(TaskQuery.tasks(tasks, in: .completed, now: now, calendar: calendar).map(\.id), [completed.id])
    }
    func testFocusPauseResumeDoesNotCountPausedTime() {
        var focus = FocusSession(taskID: UUID(), minutes: 1, now: now)
        focus.pause(at: now.addingTimeInterval(10))
        XCTAssertEqual(focus.remaining(at: now.addingTimeInterval(1000)), 50)
        XCTAssertEqual(focus.uncreditedSeconds(at: now.addingTimeInterval(1000)), 10)
        XCTAssertEqual(focus.uncreditedSeconds(at: now.addingTimeInterval(1001)), 0)
        focus.resume(at: now.addingTimeInterval(1000))
        XCTAssertEqual(focus.remaining(at: now.addingTimeInterval(1020)), 30)
        XCTAssertEqual(focus.uncreditedSeconds(at: now.addingTimeInterval(1020)), 20)
        XCTAssertEqual(focus.uncreditedSeconds(at: now.addingTimeInterval(1100)), 30)
        XCTAssertEqual(focus.uncreditedSeconds(at: now.addingTimeInterval(1200)), 0)
    }
    func testFocusDeadlineSurvivesRelaunchAndCannotGoNegative() throws {
        let focus = FocusSession(taskID: UUID(), minutes: 25, now: now)
        let restored = try JSONDecoder().decode(FocusSession.self, from: JSONEncoder().encode(focus))
        XCTAssertEqual(restored.remaining(at: now.addingTimeInterval(1400)), 100)
        XCTAssertEqual(restored.remaining(at: now.addingTimeInterval(1600)), 0)
        XCTAssertEqual(restored.elapsed(at: now.addingTimeInterval(1600)), 1500)
    }
    func testShelfCapsAtFiveDeduplicatesAndReorders() {
        let urls = (0..<7).map { URL(fileURLWithPath: "/tmp/file\($0)") }
        let first = ShelfHistory.adding(Array(urls.prefix(5)), to: [], now: now)
        XCTAssertEqual(first.map(\.path), urls.prefix(5).map(\.path))
        let second = ShelfHistory.adding([urls[3], urls[6], urls[3]], to: first, now: now)
        XCTAssertEqual(second.count, 5)
        XCTAssertEqual(second.map(\.path), [urls[3], urls[6], urls[0], urls[1], urls[2]].map(\.path))
        XCTAssertEqual(Set(second.map(\.path)).count, 5)
        XCTAssertEqual(ShelfHistory.adding([URL(string: "https://example.com")!], to: first), first)
    }
    func testStateRoundTripContainsTasksShelfActionsSettingsAndFocus() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StateRepository(url: directory.appendingPathComponent("state.json"))
        XCTAssertEqual(try repository.load(), IslandState())
        var state = IslandState()
        state.tasks = [IslandTask(title: "Проверить сохранение", createdAt: now, dueAt: now, reminderAt: now)]
        state.shelf = [ShelfEntry(path: "/tmp/example.txt", addedAt: now)]
        state.actions = [QuickAction(title: "Документы", kind: .folder, target: "/tmp")]
        state.settings.focusMinutes = 45
        state.focus = FocusSession(taskID: state.tasks[0].id, minutes: 45, now: now)
        try repository.save(state)
        XCTAssertEqual(try repository.load(), state)
        state.tasks[0].completedAt = now
        try repository.save(state)
        XCTAssertEqual(try repository.load().tasks.first?.completedAt, now)
    }
    func testCorruptStateDoesNotSilentlyBecomeEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("state.json")
        let bytes = Data("broken data".utf8); try bytes.write(to: url)
        XCTAssertThrowsError(try StateRepository(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testMediaStreamDecodesOptionalMetadataAndCalculatesPosition() throws {
        let json = #"{"type":"data","diff":false,"payload":{"title":"Трек","bundleIdentifier":"ru.yandex.desktop.music","playing":true,"elapsedTime":10,"duration":180,"playbackRate":1,"unknownField":42}}"#
        let track = try NowPlaying.decodeLine(Data(json.utf8))
        XCTAssertEqual(track.title, "Трек"); XCTAssertTrue(track.canSeek)
        XCTAssertEqual(track.position(at: now.addingTimeInterval(5), receivedAt: now), 15)
        XCTAssertEqual(track.position(at: now.addingTimeInterval(300), receivedAt: now), 180)
        XCTAssertNil(track.artworkData)
    }
    func testEmptyMediaPayloadAndPausedPosition() throws {
        let empty = try NowPlaying.decodeLine(Data(#"{"payload":{}}"#.utf8))
        XCTAssertFalse(empty.hasTrack); XCTAssertFalse(empty.canSeek)
        let paused = try NowPlaying.decodeLine(Data(#"{"payload":{"title":"Paused","playing":false,"elapsedTime":40,"duration":100}}"#.utf8))
        XCTAssertEqual(paused.position(at: now.addingTimeInterval(60), receivedAt: now), 40)
    }
    func testMediaTimestampUsesSourceClockNotDeliveryClock() throws {
        let json = #"{"payload":{"title":"Track","playing":true,"elapsedTime":10,"duration":100,"timestamp":"2027-01-15T08:00:00.000Z"}}"#
        let track = try NowPlaying.decodeLine(Data(json.utf8))
        let sourceTime = ISO8601DateFormatter().date(from: "2027-01-15T08:00:00Z")!
        XCTAssertEqual(track.position(at: sourceTime.addingTimeInterval(4), receivedAt: sourceTime.addingTimeInterval(3)), 14)
    }
}
