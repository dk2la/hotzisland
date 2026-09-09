import AppKit

@MainActor
final class MusicSource: MediaSource {
    static let bundleID = "com.apple.Music"

    private(set) var lastCommandFailed = false

    func isAvailable() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    func fetchTrack() async -> MediaTrack? {
        let script = """
        if application id "com.apple.Music" is running then
        	tell application id "com.apple.Music"
        		if player state is stopped then return "stopped"
        		set t to current track
        		return name of t & "|~|" & artist of t & "|~|" & duration of t & "|~|" & player position & "|~|" & (player state as text)
        	end tell
        end if
        """
        guard let output = await AppleScriptRunner.run(script), output != "stopped" else { return nil }
        let parts = output.components(separatedBy: "|~|")
        guard parts.count >= 5 else { return nil }
        let duration = Double(parts[2].replacingOccurrences(of: ",", with: ".")) ?? 0
        let position = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
        return MediaTrack(
            source: .appleMusic,
            title: parts[0],
            artist: parts[1],
            duration: duration,
            position: position,
            isPlaying: parts[4] == "playing",
            artworkKey: "\(parts[0])-\(parts[1])"
        )
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
    }
}
