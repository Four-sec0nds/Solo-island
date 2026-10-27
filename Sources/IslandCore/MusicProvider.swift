import Foundation

public enum MusicProvider: String, Codable, CaseIterable, Identifiable {
    case yandex, spotify, youtube, soundcloud, apple
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .yandex: return "Яндекс Музыка"
        case .spotify: return "Spotify"
        case .youtube: return "YouTube Music"
        case .soundcloud: return "SoundCloud"
        case .apple: return "Apple Music"
        }
    }
    public var url: URL {
        let address: String
        switch self {
        case .yandex: address = "https://music.yandex.ru"
        case .spotify: address = "https://open.spotify.com"
        case .youtube: address = "https://music.youtube.com"
        case .soundcloud: address = "https://soundcloud.com"
        case .apple: address = "https://music.apple.com"
        }
        return URL(string: address)!
    }
    /// Metadata is accepted only from the selected player's origins, never login pages.
    public func acceptsPlaybackHost(_ host: String) -> Bool {
        let domains: [String]
        switch self {
        case .yandex: domains = ["music.yandex.ru", "music.yandex.com", "music.yandex.kz", "music.yandex.by"]
        case .spotify: domains = ["open.spotify.com"]
        case .youtube: domains = ["music.youtube.com", "www.youtube.com", "youtube.com", "www.youtube-nocookie.com"]
        case .soundcloud: domains = ["soundcloud.com", "w.soundcloud.com"]
        case .apple: domains = ["music.apple.com"]
        }
        return domains.contains(host.lowercased())
    }
}
