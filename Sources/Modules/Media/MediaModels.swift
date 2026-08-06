import Foundation

/// A playback context. Dedicated players are controlled via AppleScript;
/// everything else (browsers, VLC, …) goes through MediaRemote.
enum MediaSourceKind: Hashable, Identifiable {
    case spotify
    case appleMusic
    case client(bundleID: String)

    var id: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .appleMusic: "com.apple.Music"
        case .client(let bundleID): bundleID
        }
    }

    /// Maps a MediaRemote client bundle ID onto a source, preferring the
    /// dedicated AppleScript-driven players.
    init(bundleID: String) {
        switch bundleID {
        case SpotifySource.bundleID: self = .spotify
        case MusicSource.bundleID: self = .appleMusic
        default: self = .client(bundleID: bundleID)
        }
    }
}

struct MediaTrack: Equatable {
    var source: MediaSourceKind
    var title: String
    var artist: String
    var duration: TimeInterval
    var position: TimeInterval
    var isPlaying: Bool
    /// Stable key identifying the artwork (URL, identifier or title fallback) —
    /// used to avoid re-fetching art on every poll tick.
    var artworkKey: String
}

enum TimeFormat {
    static func mmss(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
