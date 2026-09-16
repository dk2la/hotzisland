import AppKit

/// A controllable playback context (a dedicated player app or the system
/// now-playing item).
@MainActor
protocol MediaSource: AnyObject {
    func isAvailable() -> Bool
    /// Whether the most recent transport command failed to reach the player.
    /// Only the AppleScript sources can tell (a failed `osascript` usually
    /// means a denied Automation permission); MediaRemote has no feedback
    /// channel, so the default never reports a failure.
    var lastCommandFailed: Bool { get }
    /// Current item from whatever the source already knows (a cached
    /// notification payload, the MediaRemote item). Must not poll the
    /// player for progress — `playback` may come back `nil`.
    func fetchTrack() async -> MediaTrack?
    /// Asks the player where playback stands. Only called when `fetchTrack`
    /// returned no timing and the system item cannot supply it; the
    /// AppleScript sources answer with one `osascript` round trip.
    func fetchPlayback() async -> MediaPlayback?
    func fetchArtwork(for track: MediaTrack) async -> NSImage?
    func togglePlayPause() async
    func next() async
    func previous() async
    func like() async
    /// Jump playback to an absolute position.
    func seek(to seconds: Double) async
}

extension MediaSource {
    var lastCommandFailed: Bool { false }
    func fetchPlayback() async -> MediaPlayback? { nil }
    func like() async {}
}
