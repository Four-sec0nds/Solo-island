import Foundation

/// media-control stream --no-diff payload. Unknown fields are intentionally ignored.
public struct NowPlaying: Decodable, Equatable {
    public var bundleIdentifier: String?
    public var parentApplicationBundleIdentifier: String?
    public var title: String?
    public var artist: String?
    public var album: String?
    public var playing: Bool?
    public var duration: Double?
    public var elapsedTime: Double?
    public var playbackRate: Double?
    public var timestamp: String?
    public var artworkData: String?
    public var prohibitsSkip: Bool?
    public init() {}
    public var hasTrack: Bool { title?.isEmpty == false }
    public var isPlaying: Bool { playing == true }
    public var canSeek: Bool { (duration ?? 0) > 0 && elapsedTime != nil }
    public var applicationID: String? { parentApplicationBundleIdentifier ?? bundleIdentifier }
    public func position(at now: Date, receivedAt: Date) -> Double {
        let base = max(0, elapsedTime ?? 0)
        var sample = receivedAt
        if let timestamp {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            sample = fractional.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp) ?? receivedAt
        }
        let advancing = isPlaying ? max(0, now.timeIntervalSince(sample)) * (playbackRate ?? 1) : 0
        let position = max(0, base + advancing)
        return duration.map { min(position, max(0, $0)) } ?? position
    }
    public static func decodeLine(_ data: Data) throws -> NowPlaying {
        struct Envelope: Decodable { var payload: NowPlaying }
        return try JSONDecoder().decode(Envelope.self, from: data).payload
    }
}
