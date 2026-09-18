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
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void

    /// Posted on `NotificationCenter.default` once
    /// `MRMediaRemoteRegisterForNowPlayingNotifications` has been called —
    /// the constants' values equal their names.
    static let infoDidChange = Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
    static let applicationDidChange = Notification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification")
    static let isPlayingDidChange = Notification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")

    private enum Command: Int32 {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private let getInfo: GetInfoFn?
    private let getPID: GetPIDFn?
    private let sendCommand: SendCommandFn?
    private let setElapsed: SetElapsedFn?
    private let register: RegisterFn?
    private var lastArtworkData: Data?
    /// Title of the item `lastArtworkData` belongs to — callers borrowing
    /// the bytes for a dedicated player check they describe the same item.
    private(set) var lastTitle: String?
    /// Whether the change notifications are wired up; `false` means the
    /// register symbol is missing and the owner has to fall back to polling.
    private(set) var isObserving = false

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
        register = symbol("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterFn.self)
    }

    func isAvailable() -> Bool { getInfo != nil }

    /// Subscribes to the now-playing change notifications and forwards each
    /// one to `handler` on the main actor. Returns `false` when the register
    /// symbol is unavailable (nothing will ever be posted).
    @discardableResult
    func startObserving(_ handler: @escaping @MainActor () -> Void) -> Bool {
        guard let register, !isObserving else { return isObserving }
        register(DispatchQueue.main)
        for name in [Self.infoDidChange, Self.applicationDidChange, Self.isPlayingDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            }
        }
        isObserving = true
        return true
    }

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

    /// Bridges a MediaRemote callback into async with a deadline: if the
    /// framework never calls back (future macOS hardening), the caller gets
    /// `nil` instead of hanging the poll loop forever. Resumes exactly once.
    static func withTimeout<T: Sendable>(
        _ seconds: Double = 2,
        _ body: (@escaping @Sendable (T?) -> Void) -> Void
    ) async -> T? {
        await withCheckedContinuation { continuation in
            let box = ResumeOnce(continuation)
            body { box.resume(returning: $0) }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                box.resume(returning: nil)
            }
        }
    }

    func fetchTrack() async -> MediaTrack? {
        guard let getInfo else { return nil }
        // NOTE: MediaRemote is not guaranteed to call back (future macOS
        // hardening) — `withTimeout` turns a silent callback into `nil`.
        let raw: RawNowPlaying? = await Self.withTimeout { resume in
            getInfo(DispatchQueue.main) { dict in
                guard let info = dict as? [String: Any],
                      let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
                else {
                    resume(nil)
                    return
                }
                resume(RawNowPlaying(
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
            lastTitle = nil
            nowPlayingAppName = nil
            nowPlayingBundleID = nil
            return nil
        }

        await refreshNowPlayingApp()

        lastArtworkData = raw.artworkData
        lastTitle = raw.title

        // MediaRemote hands out the sample as-is (elapsed at `timestamp`);
        // the view derives the live position from it.
        return MediaTrack(
            source: .client(bundleID: nowPlayingBundleID ?? ""),
            title: raw.title,
            artist: raw.artist,
            duration: raw.duration,
            playback: MediaPlayback(
                elapsed: raw.elapsed,
                timestamp: raw.timestamp ?? Date(),
                rate: raw.rate
            ),
            isPlaying: raw.rate > 0,
            artworkKey: raw.artworkID ?? raw.title
        )
    }

    private func refreshNowPlayingApp() async {
        guard let getPID else { return }
        let pid: Int32? = await Self.withTimeout { resume in
            getPID(DispatchQueue.main) { resume($0) }
        }
        guard let pid, pid > 0, let app = NSRunningApplication(processIdentifier: pid) else { return }
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

/// Resume-once guard shared by a MediaRemote callback and its timeout —
/// whichever fires first wins, the other becomes a no-op.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: T?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}
