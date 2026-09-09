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
    func fetchTrack() async -> MediaTrack?
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
    func like() async {}
}
