import AppKit

/// Spotify. State arrives through the distributed notification the client
/// posts on every play/pause/track change; AppleScript is only used for
/// what the notification lacks (the artwork URL, cached per track) and for
/// the initial read when the player was already running before we subscribed.
@MainActor
final class SpotifySource: MediaSource {
    nonisolated static let bundleID = "com.spotify.client"
    static let playbackStateChanged = Notification.Name("com.spotify.client.PlaybackStateChanged")

    private(set) var lastCommandFailed = false

    /// Latest known state (notification payload or the fallback script).
    private struct State {
        var trackID: String
        var title: String
        var artist: String
        var duration: TimeInterval
        var position: TimeInterval
        var isPlaying: Bool
        var sampledAt: Date
    }

    /// `nil` until the first notification or script read; cleared when the
    /// player quits so a relaunch starts from a fresh script read.
    private var state: State?
    /// Player reported "Stopped" — nothing to show and no reason to fork.
    private var stopped = false
    /// The fallback script read failed (permission pending/denied) — do not
    /// fork again until a notification or relaunch gives a reason to.
    private var scriptReadFailed = false
    private var artworkURLs: [String: String] = [:]
    private static let artworkCacheLimit = 64

    func isAvailable() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    /// Subscribes to `com.spotify.client.PlaybackStateChanged`; `handler`
    /// runs on the main actor after the payload has been absorbed.
    func startObserving(_ handler: @escaping @MainActor () -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: Self.playbackStateChanged,
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

    /// Player quit — forget its state so nothing stale is reported.
    func forget() {
        state = nil
        stopped = false
        scriptReadFailed = false
    }

    /// Payload keys: "Track ID", "Name", "Artist", "Duration" (ms),
    /// "Playback Position" (s), "Player State" ("Playing"/"Paused"/"Stopped").
    private func absorb(_ info: PlayerInfoPayload) {
        let playerState = info.string("Player State") ?? ""
        guard playerState != "Stopped", let title = info.string("Name") else {
            state = nil
            stopped = true
            return
        }
        stopped = false
        scriptReadFailed = false
        state = State(
            trackID: info.string("Track ID") ?? title,
            title: title,
            artist: info.string("Artist") ?? "",
            duration: (info.number("Duration") ?? 0) / 1000.0,
            position: info.number("Playback Position") ?? 0,
            isPlaying: playerState == "Playing",
            sampledAt: Date()
        )
    }

    func fetchTrack() async -> MediaTrack? {
        if state == nil, !stopped, !scriptReadFailed {
            await readStateFromScript()
        }
        guard let state else { return nil }
        let artworkURL = await artworkURL(for: state.trackID)
        return MediaTrack(
            source: .spotify,
            title: state.title,
            artist: state.artist,
            duration: state.duration,
            playback: MediaPlayback(
                elapsed: state.position,
                timestamp: state.sampledAt,
                rate: state.isPlaying ? 1 : 0
            ),
            isPlaying: state.isPlaying,
            artworkKey: artworkURL ?? state.trackID
        )
    }

    /// One-off full read for a player that was already running when we
    /// subscribed — no notification describes its current item yet.
    private func readStateFromScript() async {
        let script = """
        if application id "com.spotify.client" is running then
        	tell application id "com.spotify.client"
        		if player state is stopped then return "stopped"
        		set t to current track
        		return name of t & "|~|" & artist of t & "|~|" & duration of t & "|~|" & player position & "|~|" & (player state as text) & "|~|" & artwork url of t & "|~|" & id of t
        	end tell
        end if
        """
        guard let output = await AppleScriptRunner.run(script) else {
            scriptReadFailed = true
            return
        }
        guard output != "stopped" else {
            stopped = true
            return
        }
        let parts = output.components(separatedBy: "|~|")
        guard parts.count >= 7 else { return }
        let durationMS = Double(parts[2].replacingOccurrences(of: ",", with: ".")) ?? 0
        let position = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
        let trackID = parts[6].isEmpty ? parts[0] : parts[6]
        if !parts[5].isEmpty { cacheArtworkURL(parts[5], for: trackID) }
        state = State(
            trackID: trackID,
            title: parts[0],
            artist: parts[1],
            duration: durationMS / 1000.0,
            position: position,
            isPlaying: parts[4] == "playing",
            sampledAt: Date()
        )
    }

    /// The notification carries no artwork URL — one script call per new
    /// track, remembered so a refresh never forks for a known item.
    private func artworkURL(for trackID: String) async -> String? {
        if let cached = artworkURLs[trackID] { return cached }
        let script = """
        if application id "com.spotify.client" is running then
        	tell application id "com.spotify.client"
        		set t to current track
        		return id of t & "|~|" & artwork url of t
        	end tell
        end if
        """
        guard let output = await AppleScriptRunner.run(script) else { return nil }
        let parts = output.components(separatedBy: "|~|")
        // The player may have moved on while the script ran — only trust an
        // answer that names the track we asked about.
        guard parts.count >= 2, parts[0] == trackID, !parts[1].isEmpty else { return nil }
        cacheArtworkURL(parts[1], for: trackID)
        return parts[1]
    }

    private func cacheArtworkURL(_ url: String, for trackID: String) {
        if artworkURLs.count >= Self.artworkCacheLimit { artworkURLs.removeAll() }
        artworkURLs[trackID] = url
    }

    func fetchArtwork(for track: MediaTrack) async -> NSImage? {
        guard let url = URL(string: track.artworkKey), url.scheme?.hasPrefix("http") == true,
              let (data, _) = try? await URLSession.shared.data(from: url)
        else { return nil }
        return NSImage(data: data)
    }

    func togglePlayPause() async { await command("playpause") }
    func next() async { await command("next track") }
    func previous() async { await command("previous track") }

    func seek(to seconds: Double) async {
        await command("set player position to \(Int(seconds))")
        // Spotify does not announce seeks — move the cached sample so the
        // follow-up refresh does not snap the knob back.
        if !lastCommandFailed, state != nil {
            state?.position = seconds
            state?.sampledAt = Date()
        }
    }

    /// Transport commands sit behind the same `is running` guard as
    /// `fetchTrack` — a bare `tell` would launch a quit player. The trailing
    /// `return "ok"` tells a silent success apart from a failure (osascript
    /// prints nothing to stdout in either case).
    private func command(_ body: String) async {
        let script = """
        if application id "com.spotify.client" is running then
        	tell application id "com.spotify.client"
        		\(body)
        	end tell
        	return "ok"
        end if
        """
        lastCommandFailed = await AppleScriptRunner.run(script) != "ok"
    }
}
