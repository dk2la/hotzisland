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

/// One timing sample: where playback was (`elapsed`) at `timestamp` and how
/// fast it moves (`rate`, 0 while paused). The current position is derived
/// from it on demand, so nothing has to poll the player for progress.
struct MediaPlayback: Equatable {
    var elapsed: TimeInterval
    var timestamp: Date
    var rate: Double

    func position(at date: Date) -> TimeInterval {
        elapsed + date.timeIntervalSince(timestamp) * rate
    }
}

struct MediaTrack: Equatable {
    var source: MediaSourceKind
    var title: String
    var artist: String
    var duration: TimeInterval
    /// Last timing sample; `nil` when the source knows the item but not
    /// where playback stands (position then reads as 0).
    var playback: MediaPlayback?
    var isPlaying: Bool
    /// Stable key identifying the artwork (URL, identifier or title fallback) —
    /// used to avoid re-fetching art on every refresh.
    var artworkKey: String

    /// Playback position at `date`, clamped to the track — views feed it a
    /// `TimelineView` date so progress advances without model updates.
    func position(at date: Date) -> TimeInterval {
        guard let playback else { return 0 }
        let raw = max(0, playback.position(at: date))
        return duration > 0 ? min(raw, duration) : raw
    }

    /// Same item, same state — only the timing sample may differ. Used to
    /// keep the observable `track` untouched when a player merely
    /// re-publishes its progress.
    func isSameItem(as other: MediaTrack) -> Bool {
        source == other.source && title == other.title && artist == other.artist
            && duration == other.duration && isPlaying == other.isPlaying
            && artworkKey == other.artworkKey && playback?.rate == other.playback?.rate
            && (playback == nil) == (other.playback == nil)
    }
}

enum TimeFormat {
    static func mmss(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Sendable snapshot of a player notification's userInfo: only the string
/// and numeric fields, so the payload can cross onto the main actor without
/// carrying `[AnyHashable: Any]` across isolation.
struct PlayerInfoPayload: Sendable {
    let strings: [String: String]
    let numbers: [String: Double]

    init(_ info: [AnyHashable: Any]?) {
        var strings: [String: String] = [:]
        var numbers: [String: Double] = [:]
        for (key, value) in info ?? [:] {
            guard let key = key as? String else { continue }
            if let text = value as? String {
                strings[key] = text
            } else if let number = value as? NSNumber {
                numbers[key] = number.doubleValue
            }
        }
        self.strings = strings
        self.numbers = numbers
    }

    func string(_ key: String) -> String? { strings[key] }
    func number(_ key: String) -> Double? { numbers[key] }
}
