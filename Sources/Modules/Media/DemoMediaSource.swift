import AppKit
import Foundation

/// A player that exists only in demo mode: a short playlist with drawn
/// artwork, real transport (play/pause/next/seek) and a clock that moves
/// to the next track when one ends. Presents itself as Spotify so the
/// module shows a familiar label.
@MainActor
final class DemoMediaSource: MediaSource {
    private struct Item {
        let title: String
        let artist: String
        let duration: TimeInterval
        let colors: (NSColor, NSColor)
    }

    private static let playlist: [Item] = [
        Item(title: "Golden Hour", artist: "Nova Lane", duration: 214,
             colors: (NSColor(red: 0.16, green: 0.42, blue: 0.95, alpha: 1), NSColor(red: 0.62, green: 0.20, blue: 0.85, alpha: 1))),
        Item(title: "Slow Motion", artist: "The Marlowes", duration: 187,
             colors: (NSColor(red: 0.95, green: 0.45, blue: 0.20, alpha: 1), NSColor(red: 0.90, green: 0.15, blue: 0.40, alpha: 1))),
        Item(title: "Night Drive", artist: "Keira Solis", duration: 256,
             colors: (NSColor(red: 0.10, green: 0.70, blue: 0.55, alpha: 1), NSColor(red: 0.05, green: 0.30, blue: 0.45, alpha: 1))),
        Item(title: "Weekend Radio", artist: "Lido Club", duration: 201,
             colors: (NSColor(red: 0.98, green: 0.80, blue: 0.25, alpha: 1), NSColor(red: 0.85, green: 0.35, blue: 0.10, alpha: 1))),
    ]

    private var index = 0
    private var isPlaying = true
    /// Position at `sampledAt`; the current position is derived from it.
    private var elapsed: TimeInterval = 48
    private var sampledAt = Date()
    private var advanceTask: Task<Void, Never>?
    private var artworkCache: [String: NSImage] = [:]
    /// Fired when the track changes on its own (end of track).
    var onChange: (@MainActor () -> Void)?

    init() {
        scheduleAdvance()
    }

    func stop() {
        advanceTask?.cancel()
        advanceTask = nil
    }

    private var current: Item { Self.playlist[index] }

    private var position: TimeInterval {
        let raw = isPlaying ? elapsed + Date().timeIntervalSince(sampledAt) : elapsed
        return min(max(0, raw), current.duration)
    }

    private func setPosition(_ seconds: TimeInterval) {
        elapsed = min(max(0, seconds), current.duration)
        sampledAt = Date()
        scheduleAdvance()
    }

    /// Sleeps until the current track ends, then moves on.
    private func scheduleAdvance() {
        advanceTask?.cancel()
        guard isPlaying else { return }
        let remaining = current.duration - position
        advanceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.2, remaining)))
            guard !Task.isCancelled, let self else { return }
            self.step(by: 1)
            self.onChange?()
        }
    }

    private func step(by delta: Int) {
        index = (index + delta + Self.playlist.count) % Self.playlist.count
        setPosition(0)
    }

    // MARK: - MediaSource

    func isAvailable() -> Bool { true }

    func fetchTrack() async -> MediaTrack? {
        MediaTrack(
            source: .spotify,
            title: current.title,
            artist: current.artist,
            duration: current.duration,
            playback: MediaPlayback(elapsed: position, timestamp: Date(), rate: isPlaying ? 1 : 0),
            isPlaying: isPlaying,
            artworkKey: "demo:" + current.title
        )
    }

    func fetchArtwork(for track: MediaTrack) async -> NSImage? {
        if let cached = artworkCache[track.artworkKey] { return cached }
        guard let item = Self.playlist.first(where: { "demo:" + $0.title == track.artworkKey }) else { return nil }
        let image = Self.drawArtwork(item)
        artworkCache[track.artworkKey] = image
        return image
    }

    func togglePlayPause() async {
        let now = position
        isPlaying.toggle()
        elapsed = now
        sampledAt = Date()
        scheduleAdvance()
    }

    func next() async { step(by: 1) }
    func previous() async {
        // Like a real player: early in the track, go back; otherwise restart.
        if position < 4 { step(by: -1) } else { setPosition(0) }
    }

    func seek(to seconds: Double) async { setPosition(seconds) }

    // MARK: - Artwork

    /// A gradient cover with a soft disc — enough for the accent ring and
    /// the average-colour glow, with no bundled assets.
    private static func drawArtwork(_ item: Item) -> NSImage {
        let size = NSSize(width: 300, height: 300)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(starting: item.colors.0, ending: item.colors.1)?
                .draw(in: rect, angle: 35)
            let disc = NSBezierPath(ovalIn: rect.insetBy(dx: 70, dy: 70))
            NSColor.white.withAlphaComponent(0.18).setFill()
            disc.fill()
            let hole = NSBezierPath(ovalIn: rect.insetBy(dx: 136, dy: 136))
            NSColor.black.withAlphaComponent(0.35).setFill()
            hole.fill()
            return true
        }
    }
}
