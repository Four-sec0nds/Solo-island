import Foundation

/// Browser adapters send lifecycle state only. No prompt, response, page title,
/// conversation URL, cookie or account credential is accepted by this schema.
public struct WebAgentEvent: Decodable, Sendable {
    public enum State: String, Decodable, Sendable { case start, working, finished, interrupted }
    public var provider: AgentProvider
    public var host: String
    public var session: UUID
    public var state: State
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 4096, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["provider", "host", "session", "state"]) else { throw AgentBridgeError.invalidEvent }
        let event = try JSONDecoder().decode(Self.self, from: data)
        let hosts = event.provider == .claude ? ["claude.ai", "www.claude.ai"] : ["chatgpt.com", "www.chatgpt.com"]
        guard hosts.contains(event.host) else { throw AgentBridgeError.invalidEvent }
        return event
    }
    public func bridgeEvent(instance: UUID, pid: Int32, at date: Date = Date()) throws -> AgentEvent {
        let hook: AgentHook
        switch state {
        case .start: hook = .prompt
        case .working: hook = .preTool
        case .finished: hook = .stop
        case .interrupted: hook = .interrupt
        }
        let payload = try JSONSerialization.data(withJSONObject: ["session_id": "web:" + session.uuidString,
            "hook_event_name": hook.rawValue, "cwd": host, "tool_name": "Веб"])
        return try AgentEvent(data: payload, provider: provider, instance: instance, helperPID: pid, now: date, clientPID: pid)
    }
}
