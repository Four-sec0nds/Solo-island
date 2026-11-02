import Foundation

public enum AgentHookRunner {
    /// Returns nil for normal events, timeout, app exit or cancellation. Only a
    /// matching, live, single-use reply can produce an allow/deny verdict.
    public static func run(_ event: AgentEvent, mailbox: AgentMailbox,
                           parentAlive: () -> Bool = { true },
                           pause: () -> Void = { Thread.sleep(forTimeInterval: 0.1) }) throws -> Data? {
        guard mailbox.liveHeartbeat()?.instance == event.instance else { return nil }
        try mailbox.write(event, to: mailbox.eventURL(event.id))
        guard event.hook == .permission else { return nil }
        defer {
            try? FileManager.default.removeItem(at: mailbox.eventURL(event.id))
            try? FileManager.default.removeItem(at: mailbox.replyURL(event.id))
        }
        while Date() < event.expiresAt {
            guard mailbox.liveHeartbeat()?.instance == event.instance, parentAlive() else { return nil }
            if let reply = try? mailbox.read(AgentReply.self, from: mailbox.replyURL(event.id)),
               reply.instance == event.instance, reply.request == event.id {
                return try reply.decision.hookOutput()
            }
            pause()
        }
        return nil
    }
}
