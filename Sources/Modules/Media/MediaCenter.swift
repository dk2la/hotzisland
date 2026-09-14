import AppKit
import CoreImage
import Observation
import OSLog
import SwiftUI

/// Aggregates every playback context on the machine and exposes observable
/// state for the UI.
///
/// Everything is event-driven: MediaRemote's now-playing notifications, the
/// distributed notifications Spotify and Music post, and NSWorkspace launch/
/// quit events each trigger one `refresh()`. Nothing polls while idle, and
/// progress is derived from the last timing sample by the views.
///
/// Data sources differ per context: Spotify and Apple Music are queried and
/// controlled through their notifications plus AppleScript (works even when
/// they are not the system's now-playing app), everything else through
/// MediaRemote, which only exposes the *currently* active item.
@MainActor
@Observable
final class MediaCenter {
    /// Identity and play state of the current item. Reassigned only on real
    /// changes — a player re-publishing its progress leaves it untouched, so
    /// title/artwork views are not invalidated by timing updates.
    private(set) var track: MediaTrack?
    private(set) var artwork: NSImage?
    /// Average artwork color — feeds the Glow theme's accent ring.
    private(set) var artworkAccent: Color?
    private(set) var availableSources: [MediaSourceKind] = []
    private(set) var activeSource: MediaSourceKind?

    /// Fired when playback starts/stops — the window controller uses it to
    /// flip the island between closed and compact.
    @ObservationIgnored var onPlaybackChanged: (() -> Void)?

    @ObservationIgnored private let spotify = SpotifySource()
    @ObservationIgnored private let music = MusicSource()
    @ObservationIgnored private let system = SystemNowPlayingSource()
    /// Slow safety-net poll, only when MediaRemote notifications are
    /// unavailable.
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// Debounce for notification bursts (a track change fires several).
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var lastArtworkKey: String?
    @ObservationIgnored private var wasPlaying = false
    /// Explicit user choice — auto-follow never overrides it while the
    /// source stays available.
    @ObservationIgnored private var pinnedSource: MediaSourceKind?
    /// Bundle ID of the app MediaRemote currently reports as now-playing.
    @ObservationIgnored private var activeClientBundleID: String?
    /// The MediaRemote item from the latest refresh — lends timing and
    /// artwork bytes to a dedicated player that is the now-playing app.
    @ObservationIgnored private var systemTrack: MediaTrack?
    /// Dedicated players currently running, kept current by NSWorkspace
    /// launch/quit notifications instead of a scan per refresh.
    @ObservationIgnored private var runningPlayers: Set<String> = []
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "media")
    @ObservationIgnored private var lastLoggedSources: [String] = []
    /// Last known automation-permission statuses, refreshed off-thread.
    @ObservationIgnored private var permissionCache: [String: AutomationPermission.Status] = [:]
    /// Per player: when its latest probe started. Drives the 60 s "stop
    /// waiting on a hung probe" rule; cleared when the player quits so a
    /// relaunch is probed at once.
    @ObservationIgnored private var permissionProbeStarted: [String: Date] = [:]
    /// Players whose latest probe has not returned yet.
    @ObservationIgnored private var permissionProbesInFlight: Set<String> = []
    /// Bumped by every `refresh()` call — see there.
    @ObservationIgnored private var refreshGeneration = 0

    private static let permissionProbeTimeout: TimeInterval = 60
    private static let fallbackPollInterval: Duration = .seconds(5)
    private static let refreshDebounce: Duration = .milliseconds(120)
    /// A re-published sample within this much of the derived position is
    /// the same state, not a change worth invalidating views for.
    private static let positionDriftTolerance: TimeInterval = 1

    nonisolated private static let playerBundleIDs: Set<String> = [SpotifySource.bundleID, MusicSource.bundleID]

    init() {
        let onChange: @MainActor () -> Void = { [weak self] in self?.scheduleRefresh() }
        spotify.startObserving(onChange)
        music.startObserving(onChange)
        if !system.startObserving(onChange) {
            // No change notifications — the old poll, at a lazy cadence.
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: MediaCenter.fallbackPollInterval)
                    await self?.refresh()
                }
            }
        }

        // One scan at start-up; launch/quit notifications keep it current.
        runningPlayers = Self.playerBundleIDs.intersection(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
        for bundleID in runningPlayers { probePermission(for: bundleID) }
        observeWorkspace()

        Task { await refresh() }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            // Extract the plain value before hopping: the notification itself
            // is not Sendable.
            let bundleID = Self.playerBundleID(in: note)
            MainActor.assumeIsolated {
                guard let self, let bundleID else { return }
                self.playerDidLaunch(bundleID)
            }
        }
        center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundleID = Self.playerBundleID(in: note)
            MainActor.assumeIsolated {
                guard let self, let bundleID else { return }
                self.playerDidTerminate(bundleID)
            }
        }
    }

    /// Bundle ID from a workspace launch/quit notification, if it concerns
    /// one of the dedicated players.
    nonisolated private static func playerBundleID(in note: Notification) -> String? {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier, playerBundleIDs.contains(bundleID)
        else { return nil }
        return bundleID
    }

    private func playerDidLaunch(_ bundleID: String) {
        runningPlayers.insert(bundleID)
        probePermission(for: bundleID)
        scheduleRefresh()
    }

    private func playerDidTerminate(_ bundleID: String) {
        runningPlayers.remove(bundleID)
        permissionProbeStarted[bundleID] = nil
        permissionProbesInFlight.remove(bundleID)
        switch MediaSourceKind(bundleID: bundleID) {
        case .spotify: spotify.forget()
        case .appleMusic: music.forget()
        case .client: break
        }
        scheduleRefresh()
    }

    func select(_ kind: MediaSourceKind) {
        pinnedSource = kind
        if activeSource != kind { activeSource = kind }
        Task { await refresh() }
    }

    func label(for kind: MediaSourceKind) -> String {
        switch kind {
        case .spotify: "Spotify"
        case .appleMusic: "Music"
        case .client(let bundleID): NowPlayingClients.displayName(for: bundleID)
        }
    }

    /// Whether transport commands can reach a context right now. MediaRemote
    /// only accepts commands for the active now-playing app, so inactive
    /// browser contexts are read-only until they start playing again.
    func canControl(_ kind: MediaSourceKind) -> Bool {
        switch kind {
        case .spotify, .appleMusic: true
        case .client(let bundleID): bundleID == activeClientBundleID
        }
    }

    var canControlActive: Bool {
        activeSource.map(canControl) ?? false
    }

    var supportsLike: Bool {
        activeSource == .appleMusic
    }

    /// Current playback position derived from the last timing sample —
    /// pass the date of a `TimelineView` tick to animate progress.
    func position(at date: Date) -> TimeInterval {
        track?.position(at: date) ?? 0
    }

    // MARK: - Commands

    func togglePlayPause() { command { await $0.togglePlayPause() } }
    func next() { command { await $0.next() } }
    func previous() { command { await $0.previous() } }
    func like() { command { await $0.like() } }

    /// Scrubbing. The position is applied locally at once — the follow-up
    /// refresh would otherwise snap the knob back for a moment.
    func seek(toFraction fraction: Double) {
        guard var current = track, current.duration > 0 else { return }
        let seconds = max(0, min(current.duration, fraction * current.duration))
        current.playback = MediaPlayback(
            elapsed: seconds,
            timestamp: Date(),
            rate: current.playback?.rate ?? (current.isPlaying ? 1 : 0)
        )
        track = current
        command { await $0.seek(to: seconds) }
    }

    private func command(_ operation: @escaping @MainActor (any MediaSource) async -> Void) {
        guard let activeSource, canControl(activeSource) else { return }
        let source = source(for: activeSource)
        Task {
            await operation(source)
            if source.lastCommandFailed {
                // Most likely a revoked Automation permission — re-probe now.
                probePermission(for: activeSource.id)
            }
            // Give the player a moment to apply the command before re-reading.
            try? await Task.sleep(for: .milliseconds(150))
            await refresh()
        }
    }

    // MARK: - Refresh

    private func source(for kind: MediaSourceKind) -> any MediaSource {
        switch kind {
        case .spotify: spotify
        case .appleMusic: music
        case .client: system
        }
    }

    /// Notification entry point. A single event tends to arrive as a burst
    /// (MediaRemote posts info/app/is-playing changes back to back, the
    /// player its own notification), so refreshes are coalesced.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: MediaCenter.refreshDebounce)
            guard !Task.isCancelled, let self else { return }
            await self.refresh()
        }
    }

    /// `select`, `command`, notifications and the fallback poll all call
    /// this, so passes can overlap. Rather than serialising them, each pass
    /// takes a generation number and bails out after every `await` once a
    /// newer pass has started — the newest request always wins and an older
    /// snapshot can never land on top of a newer one.
    private func refresh() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration

        let systemTrack = await system.fetchTrack()
        guard generation == refreshGeneration else { return }
        self.systemTrack = systemTrack
        activeClientBundleID = system.nowPlayingBundleID

        let sources = await discoverSources()
        guard generation == refreshGeneration else { return }
        if sources != availableSources { availableSources = sources }
        resolveActiveSource(systemIsPlaying: systemTrack?.isPlaying ?? false)

        let ids = availableSources.map(\.id)
        if ids != lastLoggedSources {
            lastLoggedSources = ids
            log.info("""
            sources=[\(ids.joined(separator: ","), privacy: .public)] \
            active=\(self.activeSource?.id ?? "nil", privacy: .public) \
            systemClient=\(self.activeClientBundleID ?? "nil", privacy: .public)
            """)
        }

        guard let activeSource else {
            apply(nil)
            return
        }

        var newTrack: MediaTrack?
        switch activeSource {
        case .spotify, .appleMusic:
            let source = source(for: activeSource)
            // The player's own notification may be unavailable (permission
            // pending, no notification yet) — fall back to system data when
            // this player is the active one.
            newTrack = await source.fetchTrack()
                ?? (activeClientBundleID == activeSource.id ? systemTrack : nil)
            guard generation == refreshGeneration else { return }
            if var track = newTrack {
                if let systemTrack, activeClientBundleID == activeSource.id, systemTrack.title == track.title {
                    // MediaRemote has the freshest sample for the now-playing
                    // app (it sees seeks the player's notification does not).
                    track.playback = systemTrack.playback
                    track.isPlaying = systemTrack.isPlaying
                } else if track.playback == nil {
                    track.playback = await source.fetchPlayback()
                    guard generation == refreshGeneration else { return }
                }
                newTrack = track
            }
        case .client(let bundleID):
            newTrack = bundleID == activeClientBundleID ? systemTrack : nil
        }
        apply(newTrack.map { track in
            var track = track
            track.source = activeSource
            return track
        })
    }

    /// Every app publishing media state, plus running dedicated players that
    /// have not published anything yet.
    private func discoverSources() async -> [MediaSourceKind] {
        var sources: [MediaSourceKind] = []
        for bundleID in await NowPlayingClients.bundleIDs() {
            let kind = MediaSourceKind(bundleID: bundleID)
            if !sources.contains(kind) { sources.append(kind) }
        }
        if runningPlayers.contains(SpotifySource.bundleID), !sources.contains(.spotify) {
            sources.append(.spotify)
        }
        if runningPlayers.contains(MusicSource.bundleID), !sources.contains(.appleMusic) {
            sources.append(.appleMusic)
        }
        return sources.filter { kind in
            switch kind {
            case .spotify:
                permissionCache[SpotifySource.bundleID, default: .undetermined] != .denied
            case .appleMusic:
                permissionCache[MusicSource.bundleID, default: .undetermined] != .denied
            case .client:
                true
            }
        }
    }

    /// Probes a player's Automation permission — on first sight of it
    /// (start-up scan or launch notification) and after a user command
    /// fails; never on a timer. Between probes the cached (or undetermined)
    /// status keeps the source visible.
    ///
    /// AEDeterminePermissionToAutomateTarget synchronously round-trips to
    /// the target app and hangs indefinitely when that app is not servicing
    /// Apple Events (observed with Spotify) — it must never run on the main
    /// thread, and a hung probe must not freeze the cache: after 60 s a new
    /// probe may start alongside it, and only the latest probe's answer is
    /// kept.
    private func probePermission(for bundleID: String) {
        guard Self.playerBundleIDs.contains(bundleID), runningPlayers.contains(bundleID) else { return }
        let now = Date()
        if permissionProbesInFlight.contains(bundleID), let started = permissionProbeStarted[bundleID],
           now.timeIntervalSince(started) < Self.permissionProbeTimeout {
            return
        }
        permissionProbeStarted[bundleID] = now
        permissionProbesInFlight.insert(bundleID)
        Task { [weak self] in
            let status = await Task.detached {
                AutomationPermission.status(towardsBundleID: bundleID)
            }.value
            guard let self, self.permissionProbeStarted[bundleID] == now else { return }
            self.permissionProbesInFlight.remove(bundleID)
            if self.permissionCache[bundleID] != status {
                self.permissionCache[bundleID] = status
                // The answer decides whether the source is listed at all.
                self.scheduleRefresh()
            }
        }
    }

    private func resolveActiveSource(systemIsPlaying: Bool) {
        let playingKind: MediaSourceKind? = if systemIsPlaying, let bundleID = activeClientBundleID {
            MediaSourceKind(bundleID: bundleID)
        } else {
            nil
        }

        if let pinned = pinnedSource, !availableSources.contains(pinned) {
            pinnedSource = nil
        }
        // Resolved locally and stored once — assigning the observable on
        // every refresh would invalidate views even when nothing changed.
        var resolved = activeSource
        if let active = resolved, !availableSources.contains(active) {
            resolved = nil
        }

        if let pinned = pinnedSource {
            resolved = pinned
        } else if resolved == nil {
            resolved = playingKind ?? availableSources.first
        } else if let playingKind, playingKind != resolved, !(track?.isPlaying ?? false) {
            // No explicit pin, the current context is silent and something
            // else is playing — follow the sound.
            resolved = playingKind
        }
        if resolved != activeSource { activeSource = resolved }
    }

    private func apply(_ newTrack: MediaTrack?) {
        let isPlaying = newTrack?.isPlaying ?? false
        let playbackChanged = isPlaying != wasPlaying
        wasPlaying = isPlaying

        let now = Date()
        if let newTrack, let current = track, current.isSameItem(as: newTrack),
           abs(current.position(at: now) - newTrack.position(at: now)) < Self.positionDriftTolerance {
            // Same item, same state, progress within tolerance of what the
            // stored sample already predicts — keep the observable as is.
        } else if newTrack != track {
            track = newTrack
        }

        if let newTrack {
            if newTrack.artworkKey != lastArtworkKey {
                lastArtworkKey = newTrack.artworkKey
                artworkTask?.cancel()
                artworkTask = Task { [weak self] in
                    guard let self else { return }
                    let image = await self.loadArtwork(for: newTrack)
                    guard !Task.isCancelled else { return }
                    if image != nil || self.artwork != nil {
                        self.artwork = image
                        self.artworkAccent = image?.averageColor
                    }
                    // Artwork often lands a beat after the metadata (the
                    // player publishes it once loaded) — an empty result is
                    // retried on the next event rather than never.
                    if image == nil { self.lastArtworkKey = nil }
                }
            }
        } else {
            if artwork != nil { artwork = nil }
            if artworkAccent != nil { artworkAccent = nil }
            lastArtworkKey = nil
        }

        if playbackChanged {
            onPlaybackChanged?()
        }
    }

    /// The system item carries the artwork bytes whenever the player is the
    /// now-playing app — no osascript/temp file (Music) or download
    /// (Spotify) needed. Otherwise ask the source.
    private func loadArtwork(for track: MediaTrack) async -> NSImage? {
        if activeClientBundleID == track.source.id, system.lastTitle == track.title,
           let image = await system.fetchArtwork(for: track) {
            return image
        }
        return await source(for: track.source).fetchArtwork(for: track)
    }
}

private extension NSImage {
    /// 1x1 CIAreaAverage reduction — cheap enough to run on artwork changes.
    var averageColor: Color? {
        guard let tiff = tiffRepresentation,
              let ciImage = CIImage(data: tiff),
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: ciImage,
                  kCIInputExtentKey: CIVector(cgRect: ciImage.extent),
              ]),
              let output = filter.outputImage
        else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return Color(
            red: Double(bitmap[0]) / 255,
            green: Double(bitmap[1]) / 255,
            blue: Double(bitmap[2]) / 255
        )
    }
}
