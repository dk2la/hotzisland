import AppKit

/// A controllable playback context (a dedicated player app or the system
/// now-playing item).
@MainActor
protocol MediaSource: AnyObject {
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

/// The two AppleScript-driven players share their transport commands.
@MainActor
protocol AppleScriptPlayer: MediaSource, Sendable {
    static var bundleID: String { get }
    var lastCommandFailed: Bool { get set }
    /// A command may have moved playback — drop whatever that invalidates.
    func commandDidRun()
    /// Takes in one player-info notification payload.
    func absorb(_ info: PlayerInfoPayload)
}

extension AppleScriptPlayer {
    func commandDidRun() {}

    /// Subscribes to the player's distributed notifications; `handler` runs
    /// on the main actor after the payload has been absorbed.
    func observe(_ names: [Notification.Name], _ handler: @escaping @MainActor () -> Void) {
        for name in names {
            DistributedNotificationCenter.default().addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let payload = PlayerInfoPayload(note.userInfo)
                MainActor.assumeIsolated {
                    self?.absorb(payload)
                    handler()
                }
            }
        }
    }

    func togglePlayPause() async { await command("playpause") }
    func next() async { await command("next track") }
    func previous() async { await command("previous track") }
    func seek(to seconds: Double) async { await command("set player position to \(Int(seconds))") }

    /// Transport commands sit behind the same `is running` guard as
    /// `fetchTrack` — a bare `tell` would launch a quit player. The trailing
    /// `return "ok"` tells a silent success apart from a failure (osascript
    /// prints nothing to stdout in either case).
    func command(_ body: String) async {
        let script = """
        if application id "\(Self.bundleID)" is running then
        	tell application id "\(Self.bundleID)"
        		\(body)
        	end tell
        	return "ok"
        end if
        """
        lastCommandFailed = await AppleScriptRunner.run(script) != "ok"
        commandDidRun()
    }
}

extension MediaSource {
    var lastCommandFailed: Bool { false }
    func fetchPlayback() async -> MediaPlayback? { nil }
    func like() async {}
}
