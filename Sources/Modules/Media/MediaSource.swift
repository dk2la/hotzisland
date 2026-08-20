import AppKit

/// A controllable playback context (a dedicated player app or the system
/// now-playing item).
@MainActor
protocol MediaSource: AnyObject {
    func isAvailable() -> Bool
    func fetchTrack() async -> MediaTrack?
    func fetchArtwork(for track: MediaTrack) async -> NSImage?
    func togglePlayPause() async
    func next() async
    func previous() async
    func like() async
}

extension MediaSource {
    func like() async {}
}
