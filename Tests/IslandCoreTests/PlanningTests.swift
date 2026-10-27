import XCTest
@testable import IslandCore

final class PlanningTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testLegacyTaskAndSettingsMigrateWithoutLosingData() throws {
        var task = IslandTask(title: "Старый проект", dueAt: now, focusedSeconds: 42)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as! [String: Any]
        object.removeValue(forKey: "alertDayBefore"); object.removeValue(forKey: "alertHourBefore")
        task = try JSONDecoder().decode(IslandTask.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(task.alertDayBefore); XCTAssertTrue(task.alertHourBefore)
        XCTAssertEqual(task.title, "Старый проект"); XCTAssertEqual(task.focusedSeconds, 42)
        let settings = try JSONDecoder().decode(IslandSettings.self, from: Data(#"{"expandedWidth":820,"focusMinutes":45,"accent":"purple"}"#.utf8))
        XCTAssertEqual(settings.expandedWidth, 820); XCTAssertEqual(settings.focusDuration, 2700)
        XCTAssertNil(settings.musicProvider); XCTAssertFalse(settings.musicOnboardingComplete)
        let unknown = try JSONDecoder().decode(IslandSettings.self, from: Data(#"{"musicProvider":"future-service"}"#.utf8))
        XCTAssertNil(unknown.musicProvider)
    }
    func testCustomFocusSupportsSecondsAndHoursAcrossRelaunch() throws {
        var settings = IslandSettings(); settings.customFocusSeconds = 2 * 3600 + 13 * 60 + 7
        let restored = try JSONDecoder().decode(IslandSettings.self, from: JSONEncoder().encode(settings))
        let focus = FocusSession(taskID: UUID(), duration: restored.focusDuration, now: now)
        XCTAssertEqual(focus.remaining(at: now.addingTimeInterval(7)), 7980)
        XCTAssertEqual(FocusSession(taskID: UUID(), duration: 1, now: now).duration, 1)
        XCTAssertEqual(FocusSession(taskID: UUID(), duration: -.infinity, now: now).duration, 1500)
    }
    func testDeadlineAlertsAreSeparateAndSkipPastTimesAndCompletedTasks() {
        let due = now.addingTimeInterval(3 * 86400)
        let task = IslandTask(title: "Сдать проект", dueAt: due, reminderAt: now.addingTimeInterval(900))
        let alerts = TaskReminderPlan.requests(for: [task], now: now)
        XCTAssertEqual(alerts.count, 3)
        XCTAssertEqual(Set(alerts.map(\.identifier)).count, 3)
        XCTAssertEqual(alerts.map(\.kind), [.manual, .dayBefore, .hourBefore])
        XCTAssertEqual(alerts[1].date, due.addingTimeInterval(-86400))
        XCTAssertEqual(alerts[2].date, due.addingTimeInterval(-3600))
        var done = task; done.completedAt = now
        XCTAssertTrue(TaskReminderPlan.requests(for: [done], now: now).isEmpty)
        XCTAssertTrue(TaskReminderPlan.requests(for: [task], now: due).isEmpty)
    }
    func testEditedDeadlinesOptOutAndDuplicateTimesDoNotDoubleNotify() {
        let due = now.addingTimeInterval(7200)
        var task = IslandTask(title: "Задача", dueAt: due, reminderAt: due.addingTimeInterval(-3600))
        XCTAssertEqual(TaskReminderPlan.requests(for: [task], now: now).count, 1)
        task.reminderAt = nil; task.alertHourBefore = false
        XCTAssertTrue(TaskReminderPlan.requests(for: [task], now: now).isEmpty)
        task.dueAt = now.addingTimeInterval(3 * 86400); task.alertDayBefore = false
        XCTAssertTrue(TaskReminderPlan.requests(for: [task], now: now).isEmpty)
    }
    func testDayBeforeRespectsCalendarAcrossDSTAndQueueRemainsBounded() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let due = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let task = IslandTask(title: "Переход времени", dueAt: due)
        let alerts = TaskReminderPlan.requests(for: [task], now: due.addingTimeInterval(-3 * 86400), calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: alerts.first!.date), 12)
        XCTAssertEqual(due.timeIntervalSince(alerts.first!.date), 23 * 3600)
        let tasks = (0..<100).map { IslandTask(title: "\($0)", dueAt: now.addingTimeInterval(Double($0 + 3) * 86400)) }
        XCTAssertEqual(TaskReminderPlan.requests(for: tasks, now: now).count, 60)
    }
    func testMusicProvidersAcceptOnlyPlaybackOrigins() {
        XCTAssertTrue(MusicProvider.yandex.acceptsPlaybackHost("music.yandex.ru"))
        XCTAssertFalse(MusicProvider.yandex.acceptsPlaybackHost("music.yandex.ru.evil.test"))
        XCTAssertFalse(MusicProvider.yandex.acceptsPlaybackHost("passport.yandex.ru"))
        XCTAssertTrue(MusicProvider.youtube.acceptsPlaybackHost("www.youtube.com"))
        XCTAssertFalse(MusicProvider.spotify.acceptsPlaybackHost("accounts.spotify.com"))
        XCTAssertEqual(Set(MusicProvider.allCases.map(\.url)).count, 5)
    }
}
