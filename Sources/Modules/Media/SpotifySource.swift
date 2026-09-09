import AppKit

@MainActor
final class SpotifySource: MediaSource {
    static let bundleID = "com.spotify.client"

    private(set) var lastCommandFailed = false

    func isAvailable() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    func fetchTrack() async -> MediaTrack? {
        let script = """
        if application id "com.spotify.client" is running then
        	tell application id "com.spotify.client"
        		if player state is stopped then return "stopped"
        		set t to current track
        		return name of t & "|~|" & artist of t & "|~|" & duration of t & "|~|" & player position & "|~|" & (player state as text) & "|~|" & artwork url of t
        	end tell
        end if
        """
        guard let output = await AppleScriptRunner.run(script), output != "stopped" else { return nil }
        let parts = output.components(separatedBy: "|~|")
        guard parts.count >= 6 else { return nil }
        let durationMS = Double(parts[2].replacingOccurrences(of: ",", with: ".")) ?? 0
        let position = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
        return MediaTrack(
            source: .spotify,
            title: parts[0],
            artist: parts[1],
            duration: durationMS / 1000.0,
            position: position,
            isPlaying: parts[4] == "playing",
            artworkKey: parts[5]
        )
    }

    func fetchArtwork(for track: MediaTrack) async -> NSImage? {
        guard let url = URL(string: track.artworkKey),
              let (data, _) = try? await URLSession.shared.data(from: url)
        else { return nil }
        return NSImage(data: data)
    }

    func togglePlayPause() async { await command("playpause") }
    func next() async { await command("next track") }
    func previous() async { await command("previous track") }
    func seek(to seconds: Double) async { await command("set player position to \(Int(seconds))") }

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
