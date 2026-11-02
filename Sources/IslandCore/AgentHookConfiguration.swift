import Foundation

public enum AgentHookConfiguration {
    public static func command(helper: String, provider: AgentProvider) -> String {
        // POSIX single-quote escaping, including user home paths containing '.
        "exec '" + helper.replacingOccurrences(of: "'", with: "'\\''") + "' hook " + provider.rawValue
    }
    public static func merging(_ data: Data?, provider: AgentProvider, helper: String, enabled: Bool) throws -> Data {
        var root: [String: Any] = [:]
        if let data {
            guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AgentBridgeError.invalidConfiguration }
            root = value
        }
        if let hooks = root["hooks"], !(hooks is [String: Any]) { throw AgentBridgeError.invalidConfiguration }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = command(helper: helper, provider: provider)
        // Recognise only our exact command, never remove another tool's hook.
        for name in Array(hooks.keys) {
            guard let groups = hooks[name] as? [[String: Any]] else { throw AgentBridgeError.invalidConfiguration }
            hooks[name] = groups.compactMap { group -> [String: Any]? in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                var group = group
                group["hooks"] = handlers.filter { ($0["command"] as? String) != command }
                return (group["hooks"] as? [[String: Any]])?.isEmpty == true ? nil : group
            }
        }
        if enabled {
            var events: [AgentHook] = [.sessionStart, .prompt, .preTool, .postTool, .permission, .stop, .sessionEnd]
            if provider == .codex { events.append(.interrupt) }
            for event in events {
                var groups = hooks[event.rawValue] as? [[String: Any]] ?? []
                groups.append(["hooks": [["type": "command", "command": command,
                    "timeout": event == .permission ? 130 : 5]]])
                hooks[event.rawValue] = groups
            }
        }
        root["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }
    public static func isEnabled(_ data: Data?, provider: AgentProvider, helper: String) -> Bool {
        guard let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any],
              let groups = hooks[AgentHook.permission.rawValue] as? [[String: Any]] else { return false }
        let command = command(helper: helper, provider: provider)
        return groups.contains { group in
            (group["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String) == command } == true
        }
    }
}
