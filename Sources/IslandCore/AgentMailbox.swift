import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct AgentHeartbeat: Codable, Sendable {
    public var instance: UUID
    public var date: Date
    public var pid: Int32
    public init(instance: UUID, date: Date = Date(), pid: Int32) { self.instance = instance; self.date = date; self.pid = pid }
}
public struct AgentReply: Codable, Sendable {
    public var instance: UUID
    public var request: UUID
    public var decision: AgentDecision
    public init(instance: UUID, request: UUID, decision: AgentDecision) { self.instance = instance; self.request = request; self.decision = decision }
}

/// User-private file transport, no listener, network access or accessibility
/// permission. Each request has a random one-shot identity and app instance.
public struct AgentMailbox: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SoloIsland/AgentBridge/runtime", isDirectory: true)
    }
    public func prepare() throws {
        for url in [root, root.appendingPathComponent("events"), root.appendingPathComponent("replies")] {
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
            }
            try check(url, directory: true)
        }
    }
    public func check(_ url: URL, directory: Bool) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_uid == getuid(),
              (info.st_mode & S_IFMT) == (directory ? S_IFDIR : S_IFREG),
              (info.st_mode & 0o077) == 0 else { throw AgentBridgeError.unsafePath }
        // Check every existing ancestor beneath runtime's parent too. In
        // particular a symlinked events/ or runtime/ must never redirect data.
        var parent = url.deletingLastPathComponent()
        while parent.path.count >= root.path.count {
            var directoryInfo = stat()
            guard lstat(parent.path, &directoryInfo) == 0, directoryInfo.st_uid == getuid(),
                  (directoryInfo.st_mode & S_IFMT) == S_IFDIR, directoryInfo.st_mode & 0o077 == 0
            else { throw AgentBridgeError.unsafePath }
            if parent == root { break }; parent.deleteLastPathComponent()
        }
    }
    public func write<T: Encodable>(_ value: T, to url: URL) throws {
        try prepare()
        // A private staging file prevents Foundation's process umask from
        // making an atomic replacement temporarily world-readable.
        let temporary = url.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw AgentBridgeError.unsafePath }
        close(fd)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try JSONEncoder().encode(value).write(to: temporary)
        guard rename(temporary.path, url.path) == 0 else { throw AgentBridgeError.unsafePath }
    }
    public func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try check(url, directory: false)
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? Int.max) <= 1024 * 1024 else { throw AgentBridgeError.invalidEvent }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
    public var heartbeatURL: URL { root.appendingPathComponent("heartbeat.json") }
    public func eventURL(_ id: UUID) -> URL { root.appendingPathComponent("events/" + id.uuidString + ".json") }
    public func replyURL(_ id: UUID) -> URL { root.appendingPathComponent("replies/" + id.uuidString + ".json") }
    public func liveHeartbeat(at now: Date = Date()) -> AgentHeartbeat? {
        guard let heartbeat = try? read(AgentHeartbeat.self, from: heartbeatURL),
              now.timeIntervalSince(heartbeat.date) >= -2, now.timeIntervalSince(heartbeat.date) < 6,
              kill(heartbeat.pid, 0) == 0 else { return nil }
        return heartbeat
    }
    public func isLive(_ event: AgentEvent, instance: UUID, at now: Date = Date()) -> Bool {
        event.instance == instance && event.hook == .permission && event.expiresAt > now
            && kill(event.helperPID, 0) == 0
            && (try? read(AgentEvent.self, from: eventURL(event.id))) == event
    }
    public func respond(to event: AgentEvent, instance: UUID, decision: AgentDecision, at now: Date = Date()) throws {
        guard isLive(event, instance: instance, at: now),
              !FileManager.default.fileExists(atPath: replyURL(event.id).path) else { throw AgentBridgeError.staleRequest }
        try write(AgentReply(instance: instance, request: event.id, decision: decision), to: replyURL(event.id))
    }
}
