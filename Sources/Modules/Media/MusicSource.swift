import AppKit

/// Apple Music. Track identity and play state arrive through the
/// `com.apple.Music.playerInfo` distributed notification; that payload has
/// no playback position, so progress is borrowed from the system item
/// (MediaRemote) whenever Music is the now-playing app and read through one
/// AppleScript call otherwise — cached until the next notification/command.
@MainActor
final class MusicSource: MediaSource {
    nonisolated static let bundleID = "com.apple.Music"
    static let playerInfo = Notification.Name("com.apple.Music.playerInfo")
    /// Older builds still post under the iTunes name.
    static let legacyPlayerInfo = Notification.Name("com.apple.iTunes.playerInfo")

    private(set) var lastCommandFailed = false

    private struct State {
        var persistentID: String?
        var title: String
        var artist: String
        var duration: TimeInterval
        var isPlaying: Bool
    }

    /// `nil` until the first notification or script read; cleared when the
    /// player quits so a relaunch starts from a fresh script read.
    private var state: State?
    /// Player reported "Stopped" — nothing to show and no reason to fork.
    private var stopped = false
    /// The fallback script read failed (permission pending/denied) — do not
    /// fork again until a notification or relaunch gives a reason to.
    private var scriptReadFailed = false
    /// Position sample taken by `fetchPlayback`; dropped whenever the
    /// notification or a command may have moved playback.
    private var playbackSample: MediaPlayback?

    func isAvailable() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    /// Subscribes to the player-info notifications; `handler` runs on the
    /// main actor after the payload has been absorbed.
    func startObserving(_ handler: @escaping @MainActor () -> Void) {
        for name in [Self.playerInfo, Self.legacyPlayerInfo] {
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

    /// Player quit — forget its state so nothing stale is reported.
    func forget() {
        state = nil
        stopped = false
        scriptReadFailed = false
        playbackSample = nil
    }

    /// Payload keys: "Name", "Artist", "Total Time" (ms), "PersistentID",
    /// "Player State" ("Playing"/"Paused"/"Stopped"). No position.
    private func absorb(_ info: PlayerInfoPayload) {
        playbackSample = nil
        let playerState = info.string("Player State") ?? ""
        guard playerState != "Stopped", let title = info.string("Name") else {
            state = nil
            stopped = true
            return
        }
        stopped = false
        scriptReadFailed = false
        state = State(
            // Same 16-digit hex form AppleScript's `persistent ID` uses, so
            // the artwork key does not flip between the two data paths.
            persistentID: info.number("PersistentID").map {
                String(format: "%016llX", UInt64(bitPattern: Int64($0)))
            },
            title: title,
            artist: info.string("Artist") ?? "",
            duration: (info.number("Total Time") ?? 0) / 1000.0,
            isPlaying: playerState == "Playing"
        )
    }

    func fetchTrack() async -> MediaTrack? {
        if state == nil, !stopped, !scriptReadFailed {
            await readStateFromScript()
        }
        guard let state else { return nil }
        return MediaTrack(
            source: .appleMusic,
            title: state.title,
            artist: state.artist,
            duration: state.duration,
            playback: playbackSample,
            isPlaying: state.isPlaying,
            artworkKey: state.persistentID ?? "\(state.title)-\(state.artist)"
        )
    }

    /// One-off full read for a player that was already running when we
    /// subscribed — no notification describes its current item yet.
    private func readStateFromScript() async {
        let script = """
        if application id "com.apple.Music" is running then
        	tell application id "com.apple.Music"
        		if player state is stopped then return "stopped"
        		set t to current track
        		return name of t & "|~|" & artist of t & "|~|" & duration of t & "|~|" & player position & "|~|" & (player state as text) & "|~|" & persistent ID of t
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
        guard parts.count >= 5 else { return }
        let duration = Double(parts[2].replacingOccurrences(of: ",", with: ".")) ?? 0
        let position = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
        let isPlaying = parts[4] == "playing"
        state = State(
            persistentID: parts.count >= 6 && !parts[5].isEmpty ? parts[5] : nil,
            title: parts[0],
            artist: parts[1],
            duration: duration,
            isPlaying: isPlaying
        )
        playbackSample = MediaPlayback(elapsed: position, timestamp: Date(), rate: isPlaying ? 1 : 0)
    }

    /// One `player position` read, kept until the next notification or
    /// command invalidates it.
    func fetchPlayback() async -> MediaPlayback? {
        if let playbackSample { return playbackSample }
        let script = """
        if application id "com.apple.Music" is running then
        	tell application id "com.apple.Music"
        		if player state is stopped then return "stopped"
        		return (player position as text) & "|~|" & (player state as text)
        	end tell
        end if
        """
        guard let output = await AppleScriptRunner.run(script), output != "stopped" else { return nil }
        let parts = output.components(separatedBy: "|~|")
        guard parts.count >= 2,
              let position = Double(parts[0].replacingOccurrences(of: ",", with: "."))
        else { return nil }
        let sample = MediaPlayback(elapsed: position, timestamp: Date(), rate: parts[1] == "playing" ? 1 : 0)
        playbackSample = sample
        return sample
    }

    /// Music has no artwork URL — AppleScript writes the raw image bytes to a
    /// temp file (printing ~1 MB as a «data tdta…» literal through the pipe
    /// was far slower), which we read back and delete.
    func fetchArtwork(for track: MediaTrack) async -> NSImage? {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("hotzisland-artwork-\(UUID().uuidString)")
        let script = """
        if application id "com.apple.Music" is running then
        	tell application id "com.apple.Music"
        		try
        			set f to open for access POSIX file "\(file.path)" with write permission
        			set eof f to 0
        			write (data of artwork 1 of current track) to f
        			close access f
        			return "ok"
        		end try
        	end tell
        end if
        """
        defer { try? FileManager.default.removeItem(at: file) }
        guard await AppleScriptRunner.run(script) == "ok",
              let data = try? Data(contentsOf: file)
        else { return nil }
        return NSImage(data: data)
    }

    func togglePlayPause() async { await command("playpause") }
    func next() async { await command("next track") }
    func previous() async { await command("previous track") }
    func seek(to seconds: Double) async { await command("set player position to \(Int(seconds))") }

    func like() async {
        await command("""
        try
        	set favorited of current track to true
        on error
        	set loved of current track to true
        end try
        """)
    }

    /// Transport commands sit behind the same `is running` guard as
    /// `fetchTrack` — a bare `tell` would launch a quit player. The trailing
    /// `return "ok"` tells a silent success apart from a failure (osascript
    /// prints nothing to stdout in either case).
    private func command(_ body: String) async {
        let script = """
        if application id "com.apple.Music" is running then
        	tell application id "com.apple.Music"
        		\(body)
        	end tell
        	return "ok"
        end if
        """
        lastCommandFailed = await AppleScriptRunner.run(script) != "ok"
        // Any command may have moved playback — the next read re-samples.
        playbackSample = nil
    }
}
