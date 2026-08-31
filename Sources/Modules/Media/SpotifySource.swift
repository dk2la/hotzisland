import AppKit

@MainActor
final class SpotifySource: MediaSource {
    static let bundleID = "com.spotify.client"

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

    func togglePlayPause() async {
        _ = await AppleScriptRunner.run("tell application id \"com.spotify.client\" to playpause")
    }

    func next() async {
        _ = await AppleScriptRunner.run("tell application id \"com.spotify.client\" to next track")
    }

    func previous() async {
        _ = await AppleScriptRunner.run("tell application id \"com.spotify.client\" to previous track")
    }

    func seek(to seconds: Double) async {
        _ = await AppleScriptRunner.run(
            "tell application id \"com.spotify.client\" to set player position to \(Int(seconds))"
        )
    }
}
