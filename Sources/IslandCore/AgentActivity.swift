import Foundation

public enum AgentProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case claude, codex
    public var id: String { rawValue }
    public var title: String { self == .claude ? "Claude Code" : "Codex" }
    public var configDirectory: String { self == .claude ? ".claude" : ".codex" }
    public var configFilename: String { self == .claude ? "settings.json" : "hooks.json" }
}

public enum AgentHook: String, Codable, Sendable {
    case sessionStart = "SessionStart", prompt = "UserPromptSubmit", preTool = "PreToolUse"
    case postTool = "PostToolUse", permission = "PermissionRequest", stop = "Stop"
    case sessionEnd = "SessionEnd", interrupt = "Interrupt"
}

/// Only the fields needed for presentation cross the local bridge. Prompts,
/// transcripts, credentials and full tool results are never retained.
public struct AgentEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var instance: UUID
    public var provider: AgentProvider
    public var sessionID: String
    public var hook: AgentHook
    public var date: Date
    public var cwd: String
    public var tool: String
    public var input: String?
    public var helperPID: Int32
    public var expiresAt: Date

    public init(data: Data, provider: AgentProvider, instance: UUID, helperPID: Int32,
                now: Date = Date(), lifetime: TimeInterval = 120) throws {
        guard data.count <= 512 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["hook_event_name"] as? String, let hook = AgentHook(rawValue: name),
              let session = object["session_id"] as? String, !session.isEmpty, session.count <= 512
        else { throw AgentBridgeError.invalidEvent }
        id = UUID(); self.instance = instance; self.provider = provider; sessionID = session
        if let child = object["agent_id"] as? String, !child.isEmpty { sessionID += ":" + String(child.prefix(256)) }
        self.hook = hook; date = now; self.helperPID = helperPID; expiresAt = now.addingTimeInterval(lifetime)
        cwd = String((object["cwd"] as? String ?? "").prefix(4096))
        tool = String((object["tool_name"] as? String ?? "").prefix(256))
        if hook == .permission {
            guard let value = object["tool_input"], JSONSerialization.isValidJSONObject(value) else {
                throw AgentBridgeError.invalidEvent
            }
            let bytes = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
            input = String(decoding: bytes, as: UTF8.self)
        }
    }
    public var sessionKey: String { provider.rawValue + ":" + sessionID }
    public var project: String { URL(fileURLWithPath: cwd).lastPathComponent.isEmpty ? "Проект" : URL(fileURLWithPath: cwd).lastPathComponent }
}

public enum AgentBridgeError: Error { case invalidEvent, unsafePath, staleRequest, invalidConfiguration }

public struct AgentSession: Identifiable, Equatable, Sendable {
    public enum Status: String, Sendable { case working, waiting, finished, interrupted, unknown }
    public var id: String
    public var provider: AgentProvider
    public var project: String
    public var cwd: String
    public var startedAt: Date
    public var updatedAt: Date
    public var endedAt: Date?
    public var status: Status
    public var tool: String
    public var pending: [AgentEvent]
    public func elapsed(at date: Date) -> TimeInterval { max(0, (endedAt ?? date).timeIntervalSince(startedAt)) }
    public func clock(at date: Date) -> String {
        let minutes = Int(elapsed(at: date) / 60)
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

public struct AgentActivity: Sendable {
    public private(set) var sessions: [AgentSession] = []
    public init() {}
    public var pending: [AgentEvent] { sessions.flatMap(\.pending).sorted { $0.date < $1.date } }
    public var current: AgentSession? {
        sessions.first { $0.status == .waiting } ?? sessions.first { $0.status == .working }
    }
    public mutating func ingest(_ event: AgentEvent) {
        let index = sessions.firstIndex { $0.id == event.sessionKey }
        var session = index.map { sessions[$0] } ?? AgentSession(id: event.sessionKey, provider: event.provider,
            project: event.project, cwd: event.cwd, startedAt: event.date, updatedAt: event.date,
            status: .unknown, tool: "", pending: [])
        guard event.date >= session.updatedAt else { return }
        if event.hook == .prompt || ((session.status == .finished || session.status == .interrupted || session.status == .unknown)
                                    && (event.hook == .preTool || event.hook == .permission)) {
            session.startedAt = event.date; session.endedAt = nil
        }
        session.updatedAt = event.date
        if !event.tool.isEmpty { session.tool = event.tool }
        switch event.hook {
        case .sessionStart: break
        case .prompt, .preTool, .postTool:
            session.status = session.pending.isEmpty ? .working : .waiting
        case .permission:
            if !session.pending.contains(where: { $0.id == event.id }) { session.pending.append(event) }
            session.status = .waiting
        case .stop, .sessionEnd, .interrupt:
            session.status = event.hook == .interrupt ? .interrupted : .finished
            session.endedAt = event.date; session.pending = []
        }
        if let index { sessions.remove(at: index) }
        sessions.insert(session, at: 0)
        // Active sessions and unresolved requests are never discarded to make
        // room for completed history. History itself is memory-only and bounded.
        var historyCount = 0
        sessions.removeAll { session in
            guard session.status != .working && session.status != .waiting else { return false }
            historyCount += 1; return historyCount > 8
        }
    }
    public mutating func resolved(_ id: UUID, at date: Date, inClient: Bool = false) {
        for index in sessions.indices where sessions[index].pending.contains(where: { $0.id == id }) {
            sessions[index].pending.removeAll { $0.id == id }
            sessions[index].status = sessions[index].pending.isEmpty ? (inClient ? .unknown : .working) : .waiting
            if inClient && sessions[index].pending.isEmpty { sessions[index].endedAt = date }
            sessions[index].updatedAt = date
        }
    }
    public mutating func expire(at now: Date, requestAlive: (AgentEvent) -> Bool) {
        for index in sessions.indices {
            let previous = sessions[index].pending.count
            sessions[index].pending.removeAll { $0.expiresAt <= now || !requestAlive($0) }
            if previous > 0 && sessions[index].pending.isEmpty {
                sessions[index].status = .unknown; sessions[index].endedAt = now
            }
            // A missing Stop must not leave a forever-running timer. We cannot
            // infer a client's work after a long gap without lifecycle events.
            if sessions[index].status == .working && now.timeIntervalSince(sessions[index].updatedAt) > 3600 {
                sessions[index].status = .unknown; sessions[index].endedAt = now
            }
        }
    }
}

public enum AgentDecision: String, Codable, Sendable {
    case allow, deny, client
    public func hookOutput() throws -> Data {
        if self == .client { return Data() }
        var decision: [String: Any] = ["behavior": rawValue]
        if self == .deny { decision["message"] = "Отклонено пользователем в Solo Island." }
        return try JSONSerialization.data(withJSONObject: ["hookSpecificOutput": [
            "hookEventName": "PermissionRequest", "decision": decision]], options: [.sortedKeys])
    }
}
