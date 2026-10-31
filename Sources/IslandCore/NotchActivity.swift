import Foundation

/// Presentation policy for the small, passive wings around the camera cutout.
/// Focus owns the time display while music can keep its playback indicator.
public enum NotchActivity: Equatable, Sendable {
    public enum Playback: Equatable, Sendable { case playing, paused }
    case hidden
    case music(Playback)
    case focus(paused: Bool, music: Playback?)

    public init(track: NowPlaying, focus: FocusSession?) {
        let music: Playback? = track.hasTrack ? (track.isPlaying ? .playing : .paused) : nil
        if let focus { self = .focus(paused: focus.isPaused, music: music) }
        else if let music { self = .music(music) }
        else { self = .hidden }
    }

    public var isVisible: Bool { self != .hidden }
}

/// A playback-state animation, not an audio level or frequency measurement.
/// The playback clock and track identity drive it; pause/Reduce Motion is static.
public enum PlaybackIndicator {
    public static func levels(position: Double, identity: String, moving: Bool) -> [Double] {
        guard moving else { return [0.28, 0.48, 0.34] }
        let time = position.isFinite ? max(0, position) : 0
        let seed = identity.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        let phase = Double(seed % 628) / 100
        var levels: [Double] = []
        for index in 0..<3 {
            let speed: Double = 3.1 + Double(index) * 0.7
            let offset: Double = phase + Double(index) * 1.9
            let wave: Double = sin(time * speed + offset)
            levels.append(0.25 + 0.75 * (wave + 1) / 2)
        }
        return levels
    }
}
