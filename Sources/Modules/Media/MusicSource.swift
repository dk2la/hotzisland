import AppKit

@MainActor
final class MusicSource: MediaSource {
    static let bundleID = "com.apple.Music"

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

    /// Music has no artwork URL — AppleScript returns raw image bytes printed
    /// as an AppleScript data literal («data tdta<hex>»), which we decode.
    func fetchArtwork(for track: MediaTrack) async -> NSImage? {
        let script = """
        if application id "com.apple.Music" is running then
        	tell application id "com.apple.Music"
        		try
        			return data of artwork 1 of current track
        		end try
        	end tell
        end if
        """
        guard let output = await AppleScriptRunner.run(script),
              let marker = output.range(of: "tdta")
        else { return nil }
        let hex = output[marker.upperBound...]
            .replacingOccurrences(of: "»", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(hexString: hex) else { return nil }
        return NSImage(data: data)
    }

    func togglePlayPause() async {
        _ = await AppleScriptRunner.run("tell application id \"com.apple.Music\" to playpause")
    }

    func next() async {
        _ = await AppleScriptRunner.run("tell application id \"com.apple.Music\" to next track")
    }

    func previous() async {
        _ = await AppleScriptRunner.run("tell application id \"com.apple.Music\" to previous track")
    }

    func like() async {
        _ = await AppleScriptRunner.run("""
        tell application id "com.apple.Music"
        	try
        		set favorited of current track to true
        	on error
        		set loved of current track to true
        	end try
        end tell
        """)
    }
}

private extension Data {
    init?(hexString: String) {
        let chars = Array(hexString.utf8)
        guard chars.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)

        func value(_ c: UInt8) -> UInt8? {
            switch c {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): c - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): c - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): c - UInt8(ascii: "A") + 10
            default: nil
            }
        }

        var index = 0
        while index < chars.count {
            guard let high = value(chars[index]), let low = value(chars[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
            index += 2
        }
        self.init(bytes)
    }
}
