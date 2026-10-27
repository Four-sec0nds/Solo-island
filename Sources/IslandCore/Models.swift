import Foundation

public struct IslandTask: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var dueAt: Date?
    public var reminderAt: Date?
    public var completedAt: Date?
    public var focusedSeconds: Int
    public var alertDayBefore: Bool
    public var alertHourBefore: Bool

    public init(id: UUID = UUID(), title: String, createdAt: Date = Date(), dueAt: Date? = nil,
                reminderAt: Date? = nil, completedAt: Date? = nil, focusedSeconds: Int = 0,
                alertDayBefore: Bool = true, alertHourBefore: Bool = true) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.dueAt = dueAt
        self.reminderAt = reminderAt; self.completedAt = completedAt; self.focusedSeconds = focusedSeconds
        self.alertDayBefore = alertDayBefore; self.alertHourBefore = alertHourBefore
    }
    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, dueAt, reminderAt, completedAt, focusedSeconds, alertDayBefore, alertHourBefore
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        reminderAt = try c.decodeIfPresent(Date.self, forKey: .reminderAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        focusedSeconds = try c.decodeIfPresent(Int.self, forKey: .focusedSeconds) ?? 0
        alertDayBefore = try c.decodeIfPresent(Bool.self, forKey: .alertDayBefore) ?? true
        alertHourBefore = try c.decodeIfPresent(Bool.self, forKey: .alertHourBefore) ?? true
    }
    public var isCompleted: Bool { completedAt != nil }
    public func isOverdue(at now: Date) -> Bool { !isCompleted && dueAt.map { $0 < now } == true }
}

public enum TaskList: String, CaseIterable, Identifiable {
    case today = "Сегодня", upcoming = "Предстоящие", completed = "Выполненные"
    public var id: String { rawValue }
}

public enum TaskQuery {
    public static func tasks(_ tasks: [IslandTask], in list: TaskList, now: Date = Date(),
                             calendar: Calendar = .current) -> [IslandTask] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return tasks.filter { task in
            switch list {
            case .completed: return task.isCompleted
            case .today: return !task.isCompleted && (task.dueAt == nil || task.dueAt! < tomorrow)
            case .upcoming: return !task.isCompleted && task.dueAt.map { $0 >= tomorrow } == true
            }
        }.sorted { lhs, rhs in
            if list == .completed { return lhs.completedAt! > rhs.completedAt! }
            return (lhs.dueAt ?? .distantFuture, lhs.createdAt) < (rhs.dueAt ?? .distantFuture, rhs.createdAt)
        }
    }
}

public struct FocusSession: Codable, Equatable {
    public var taskID: UUID
    public var duration: TimeInterval
    public var remainingWhenPaused: TimeInterval
    public var deadline: Date?
    public var creditedSeconds: Int

    public init(taskID: UUID, minutes: Int, now: Date = Date()) {
        self.init(taskID: taskID, duration: Double(max(1, minutes)) * 60, now: now)
    }
    public init(taskID: UUID, duration seconds: TimeInterval, now: Date = Date()) {
        self.taskID = taskID; duration = seconds.isFinite ? min(359999, max(1, seconds)) : 1500
        remainingWhenPaused = duration; deadline = now.addingTimeInterval(duration); creditedSeconds = 0
    }
    public var isPaused: Bool { deadline == nil }
    public func remaining(at now: Date) -> TimeInterval { max(0, deadline.map { $0.timeIntervalSince(now) } ?? remainingWhenPaused) }
    public func elapsed(at now: Date) -> Int { Int(max(0, duration - remaining(at: now))) }
    public mutating func pause(at now: Date) {
        remainingWhenPaused = remaining(at: now); deadline = nil
    }
    public mutating func resume(at now: Date) {
        guard isPaused, remainingWhenPaused > 0 else { return }
        deadline = now.addingTimeInterval(remainingWhenPaused)
    }
    public mutating func uncreditedSeconds(at now: Date) -> Int {
        let total = elapsed(at: now)
        let delta = max(0, total - creditedSeconds)
        creditedSeconds = max(creditedSeconds, total)
        return delta
    }
}

public enum ShelfKind: String, Codable { case file, text, image }

public struct ShelfEntry: Identifiable, Codable, Equatable {
    public var id: UUID
    public var path: String
    public var addedAt: Date
    public var kind: ShelfKind
    public var text: String?
    public var isPinned: Bool
    public init(path: String = "", addedAt: Date = Date(), kind: ShelfKind = .file, text: String? = nil, isPinned: Bool = false) {
        id = UUID(); self.path = path; self.addedAt = addedAt
        self.kind = kind; self.text = text; self.isPinned = isPinned
    }
    public var url: URL { URL(fileURLWithPath: path) }
    public var identity: String { kind == .text ? "text:" + (text ?? "") : kind.rawValue + ":" + path }
    enum CodingKeys: String, CodingKey { case id, path, addedAt, kind, text, isPinned }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        path = try values.decodeIfPresent(String.self, forKey: .path) ?? ""
        addedAt = try values.decode(Date.self, forKey: .addedAt)
        kind = try values.decodeIfPresent(ShelfKind.self, forKey: .kind) ?? .file
        text = try values.decodeIfPresent(String.self, forKey: .text)
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

public enum ShelfHistory {
    /// Five recent files, twenty text snippets and twenty unpinned images; pins are retained until removed.
    public static func inserting(_ entries: [ShelfEntry], to existing: [ShelfEntry]) -> [ShelfEntry] {
        var result = existing
        for var entry in entries.reversed() {
            if let old = result.first(where: { $0.identity == entry.identity }) {
                entry.id = old.id; entry.isPinned = old.isPinned || entry.isPinned
            }
            result.removeAll { $0.identity == entry.identity }
            result.insert(entry, at: 0)
        }
        var counts: [ShelfKind: Int] = [:]
        return result.filter { entry in
            if entry.isPinned { return true }
            let count = (counts[entry.kind] ?? 0) + 1; counts[entry.kind] = count
            return count <= (entry.kind == .file ? 5 : 20)
        }
    }
    public static func adding(_ urls: [URL], to entries: [ShelfEntry], now: Date = Date()) -> [ShelfEntry] {
        inserting(urls.filter(\.isFileURL).map { ShelfEntry(path: $0.standardizedFileURL.path, addedAt: now) }, to: entries)
    }
}

public enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case application = "Приложение", folder = "Папка", shortcut = "Быстрая команда"
    public var id: String { rawValue }
}
public struct QuickAction: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var kind: ActionKind
    public var target: String
    public init(title: String, kind: ActionKind, target: String) {
        id = UUID(); self.title = title; self.kind = kind; self.target = target
    }
}

public struct IslandSettings: Codable, Equatable {
    public var expandedWidth: Double = 720
    public var cornerRadius: Double = 30
    public var animationDuration: Double = 0.25
    public var coverAccent: Bool = true
    public var accent: String = "mint"
    public var focusMinutes: Int = 25
    public var focusShortcut: String = ""
    public var endFocusShortcut: String = ""
    public var customFocusSeconds: Int?
    public var musicProvider: MusicProvider?
    public var musicOnboardingComplete = false
    public init() {}
    public var focusDuration: TimeInterval { Double(customFocusSeconds.map { min(359999, max(1, $0)) } ?? min(5999, max(1, focusMinutes)) * 60) }
    private enum CodingKeys: String, CodingKey {
        case expandedWidth, cornerRadius, animationDuration, coverAccent, accent, focusMinutes, focusShortcut, endFocusShortcut
        case customFocusSeconds, musicProvider, musicOnboardingComplete
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        expandedWidth = try c.decodeIfPresent(Double.self, forKey: .expandedWidth) ?? 720
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 30
        animationDuration = try c.decodeIfPresent(Double.self, forKey: .animationDuration) ?? 0.25
        coverAccent = try c.decodeIfPresent(Bool.self, forKey: .coverAccent) ?? true
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? "mint"
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25
        focusShortcut = try c.decodeIfPresent(String.self, forKey: .focusShortcut) ?? ""
        endFocusShortcut = try c.decodeIfPresent(String.self, forKey: .endFocusShortcut) ?? ""
        customFocusSeconds = try c.decodeIfPresent(Int.self, forKey: .customFocusSeconds)
        if let raw = try c.decodeIfPresent(String.self, forKey: .musicProvider) { musicProvider = MusicProvider(rawValue: raw) }
        musicOnboardingComplete = try c.decodeIfPresent(Bool.self, forKey: .musicOnboardingComplete) ?? false
    }
}

public struct IslandState: Codable, Equatable {
    public var schemaVersion: Int = 1
    public var tasks: [IslandTask] = []
    public var shelf: [ShelfEntry] = []
    public var actions: [QuickAction] = []
    public var focus: FocusSession?
    public var settings = IslandSettings()
    public init() {}
}

public final class StateRepository {
    public let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    public init(url: URL) {
        self.url = url
        encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    }
    public func load() throws -> IslandState {
        guard FileManager.default.fileExists(atPath: url.path) else { return IslandState() }
        let state = try decoder.decode(IslandState.self, from: Data(contentsOf: url))
        guard state.schemaVersion == 1 else { throw CocoaError(.fileReadUnknown) }
        return state
    }
    public func save(_ state: IslandState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
