import AppKit

/// System-wide "now playing" via the private MediaRemote framework — covers
/// browsers (YouTube etc.) and any app that publishes playback state.
/// Loaded dynamically; if Apple ever blocks access this source simply
/// reports nothing and the dedicated AppleScript sources keep working.
@MainActor
final class SystemNowPlayingSource: MediaSource {
    /// App currently publishing now-playing state (e.g. "Chrome").
    private(set) var nowPlayingAppName: String?
    private(set) var nowPlayingBundleID: String?

    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
    private typealias GetPIDFn = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool
    private typealias SetElapsedFn = @convention(c) (Double) -> Void

    private enum Command: Int32 {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private let getInfo: GetInfoFn?
    private let getPID: GetPIDFn?
    private let sendCommand: SendCommandFn?
    private let setElapsed: SetElapsedFn?
    private var lastArtworkData: Data?

    init() {
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW
        )
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let sym = dlsym(handle, name) else { return nil }
            return unsafeBitCast(sym, to: T.self)
        }
        getInfo = symbol("MRMediaRemoteGetNowPlayingInfo", as: GetInfoFn.self)
        getPID = symbol("MRMediaRemoteGetNowPlayingApplicationPID", as: GetPIDFn.self)
        sendCommand = symbol("MRMediaRemoteSendCommand", as: SendCommandFn.self)
        setElapsed = symbol("MRMediaRemoteSetElapsedTime", as: SetElapsedFn.self)
    }

    func isAvailable() -> Bool { getInfo != nil }

    /// Sendable snapshot extracted from the MediaRemote info dictionary
    /// inside the callback (the raw dictionary must not cross isolation).
    private struct RawNowPlaying: Sendable {
        var title: String
        var artist: String
        var duration: Double
        var elapsed: Double
        var rate: Double
        var timestamp: Date?
        var artworkData: Data?
        var artworkID: String?
    }

    func fetchTrack() async -> MediaTrack? {
        guard let getInfo else { return nil }
        // NOTE: if MediaRemote stops invoking callbacks (future macOS
        // hardening), this await would hang the poll loop — revisit with a
        // timeout when that becomes real.
        let raw: RawNowPlaying? = await withCheckedContinuation { continuation in
            getInfo(DispatchQueue.main) { dict in
                guard let info = dict as? [String: Any],
                      let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: RawNowPlaying(
                    title: title,
                    artist: info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
                    duration: info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0,
                    elapsed: info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0,
                    rate: info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0,
                    timestamp: info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date,
                    artworkData: info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
                    artworkID: info["kMRMediaRemoteNowPlayingInfoArtworkIdentifier"] as? String
                ))
            }
        }
        guard let raw else {
            lastArtworkData = nil
            nowPlayingAppName = nil
            nowPlayingBundleID = nil
            return nil
        }

        await refreshNowPlayingApp()

        var elapsed = raw.elapsed
        if raw.rate > 0, let timestamp = raw.timestamp {
            elapsed += Date().timeIntervalSince(timestamp) * raw.rate
        }
        lastArtworkData = raw.artworkData

        return MediaTrack(
            source: .client(bundleID: nowPlayingBundleID ?? ""),
            title: raw.title,
            artist: raw.artist,
            duration: raw.duration,
            position: elapsed,
            isPlaying: raw.rate > 0,
            artworkKey: raw.artworkID ?? raw.title
        )
    }

    private func refreshNowPlayingApp() async {
        guard let getPID else { return }
        let pid: Int32 = await withCheckedContinuation { continuation in
            getPID(DispatchQueue.main) { continuation.resume(returning: $0) }
        }
        guard pid > 0, let app = NSRunningApplication(processIdentifier: pid) else { return }
        nowPlayingAppName = app.localizedName
        nowPlayingBundleID = app.bundleIdentifier
    }

    func fetchArtwork(for track: MediaTrack) async -> NSImage? {
        guard let data = lastArtworkData else { return nil }
        return NSImage(data: data)
    }

    func togglePlayPause() async { send(.togglePlayPause) }
    func next() async { send(.nextTrack) }
    func previous() async { send(.previousTrack) }
    func seek(to seconds: Double) async { setElapsed?(seconds) }

    private func send(_ command: Command) {
        _ = sendCommand?(command.rawValue, nil)
    }
}
