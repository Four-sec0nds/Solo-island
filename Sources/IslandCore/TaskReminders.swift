import Foundation

public struct TaskReminder: Equatable {
    public enum Kind: String { case manual, dayBefore, hourBefore }
    public let taskID: UUID
    public let kind: Kind
    public let date: Date
    public var identifier: String { "task.\(taskID).\(kind.rawValue)" }
    public var title: String {
        switch kind {
        case .manual: return "Пора заняться задачей"
        case .dayBefore: return "До дедлайна — один день"
        case .hourBefore: return "До дедлайна — один час"
        }
    }
}

public enum TaskReminderPlan {
    public static func requests(for tasks: [IslandTask], now: Date = Date(), calendar: Calendar = .current) -> [TaskReminder] {
        var result: [TaskReminder] = []
        for task in tasks where !task.isCompleted {
            var candidates: [(TaskReminder.Kind, Date?)] = [(.manual, task.reminderAt)]
            if let due = task.dueAt {
                if task.alertDayBefore { candidates.append((.dayBefore, calendar.date(byAdding: .day, value: -1, to: due))) }
                if task.alertHourBefore { candidates.append((.hourBefore, calendar.date(byAdding: .hour, value: -1, to: due))) }
            }
            var seen: [Date] = []
            for (kind, candidate) in candidates {
                guard let date = candidate, date > now, !seen.contains(where: { abs($0.timeIntervalSince(date)) < 1 }) else { continue }
                seen.append(date); result.append(TaskReminder(taskID: task.id, kind: kind, date: date))
            }
        }
        // Leave space for a focus completion notification in the system queue.
        return Array(result.sorted { $0.date == $1.date ? $0.identifier < $1.identifier : $0.date < $1.date }.prefix(60))
    }
}
