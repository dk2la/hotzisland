import AppKit
import CoreImage
import Observation
import OSLog
import SwiftUI

/// Aggregates every playback context on the machine, polls the selected one
/// and exposes observable state for the UI.
///
/// Data sources differ per context: Spotify and Apple Music are queried and
/// controlled through AppleScript (works even when they are not the system's
/// now-playing app), everything else through MediaRemote, which only exposes
/// the *currently* active item.
@MainActor
@Observable
final class MediaCenter {
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
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var lastArtworkKey: String?
    @ObservationIgnored private var wasPlaying = false
    /// Explicit user choice — auto-follow never overrides it while the
    /// source stays available.
    @ObservationIgnored private var pinnedSource: MediaSourceKind?
    /// Bundle ID of the app MediaRemote currently reports as now-playing.
    @ObservationIgnored private var activeClientBundleID: String?
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "media")
    @ObservationIgnored private var lastLoggedSources: [String] = []
    /// Last known automation-permission statuses, refreshed off-thread.
    @ObservationIgnored private var permissionCache: [String: AutomationPermission.Status] = [:]
    /// Per player: when its latest probe started. Drives the 30 s cadence
    /// and the 60 s "stop waiting on a hung probe" rule; cleared when the
    /// player quits so a relaunch is probed at once.
    @ObservationIgnored private var permissionProbeStarted: [String: Date] = [:]
    /// Players whose latest probe has not returned yet.
    @ObservationIgnored private var permissionProbesInFlight: Set<String> = []
    /// Players whose last user command failed — re-probed on the next tick
    /// instead of waiting out the cadence.
    @ObservationIgnored private var permissionRecheckRequested: Set<String> = []
    /// Bumped by every `refresh()` call — see there.
    @ObservationIgnored private var refreshGeneration = 0

    private static let permissionProbeInterval: TimeInterval = 30
    private static let permissionProbeTimeout: TimeInterval = 60
    /// Idle back-off: a silent machine is refreshed every N ticks.
    private static let idleTicksPerRefresh = 3

    init() {
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                // Every tick while playing (the progress bar needs it), every
                // third tick otherwise — a refresh costs MediaRemote calls, a
                // running-app scan and an osascript fork for Spotify/Music.
                if let self, self.track?.isPlaying == true || tick % MediaCenter.idleTicksPerRefresh == 0 {
                    await self.refresh()
                }
                tick += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
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

    // MARK: - Commands

    func togglePlayPause() { command { await $0.togglePlayPause() } }
    func next() { command { await $0.next() } }
    func previous() { command { await $0.previous() } }
    func like() { command { await $0.like() } }

    /// Scrubbing. The position is applied locally at once — the next poll
    /// would otherwise snap the knob back for up to a second.
    func seek(toFraction fraction: Double) {
        guard var current = track, current.duration > 0 else { return }
        let seconds = max(0, min(current.duration, fraction * current.duration))
        current.position = seconds
        track = current
        command { await $0.seek(to: seconds) }
    }

    private func command(_ operation: @escaping @MainActor (any MediaSource) async -> Void) {
        guard let activeSource, canControl(activeSource) else { return }
        let source = source(for: activeSource)
        Task {
            await operation(source)
            if source.lastCommandFailed {
                // Most likely a revoked Automation permission — re-probe on
                // the next tick rather than after the regular cadence.
                permissionRecheckRequested.insert(activeSource.id)
            }
            // Give the player a moment to apply the command before re-reading.
            try? await Task.sleep(for: .milliseconds(150))
            await refresh()
        }
    }

    // MARK: - Polling

    private func source(for kind: MediaSourceKind) -> any MediaSource {
        switch kind {
        case .spotify: spotify
        case .appleMusic: music
        case .client: system
        }
    }

    /// `select`, `command` and the poll loop all call this, so passes can
    /// overlap. Rather than serialising them, each pass takes a generation
    /// number and bails out after every `await` once a newer pass has
    /// started — the newest request always wins and an older snapshot can
    /// never land on top of a newer one.
    private func refresh() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration

        let systemTrack = await system.fetchTrack()
        guard generation == refreshGeneration else { return }
        activeClientBundleID = system.nowPlayingBundleID

        let sources = await discoverSources(running: runningPlayers())
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

        let newTrack: MediaTrack?
        switch activeSource {
        case .spotify, .appleMusic:
            // AppleScript may be unavailable (permission pending) — fall back
            // to system data when this player is the active one.
            newTrack = await source(for: activeSource).fetchTrack()
                ?? (activeClientBundleID == activeSource.id ? systemTrack : nil)
        case .client(let bundleID):
            newTrack = bundleID == activeClientBundleID ? systemTrack : nil
        }
        guard generation == refreshGeneration else { return }
        apply(newTrack.map { track in
            var track = track
            track.source = activeSource
            return track
        })
    }

    /// Bundle IDs of the dedicated players currently running — one scan per
    /// tick, shared by source discovery and the permission scheduler instead
    /// of a `runningApplications(withBundleIdentifier:)` lookup per player.
    private func runningPlayers() -> Set<String> {
        let players: Set<String> = [SpotifySource.bundleID, MusicSource.bundleID]
        return players.intersection(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    /// Every app publishing media state, plus running dedicated players that
    /// have not published anything yet.
    private func discoverSources(running: Set<String>) async -> [MediaSourceKind] {
        var sources: [MediaSourceKind] = []
        for bundleID in await NowPlayingClients.bundleIDs() {
            let kind = MediaSourceKind(bundleID: bundleID)
            if !sources.contains(kind) { sources.append(kind) }
        }
        if running.contains(SpotifySource.bundleID), !sources.contains(.spotify) {
            sources.append(.spotify)
        }
        if running.contains(MusicSource.bundleID), !sources.contains(.appleMusic) {
            sources.append(.appleMusic)
        }
        refreshPermissionCache(running: running)
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

    /// Probes each running player at most every 30 s — immediately on first
    /// sight of it, and once more after a user command fails. Between probes
    /// the cached (or undetermined) status keeps the source visible.
    ///
    /// AEDeterminePermissionToAutomateTarget synchronously round-trips to
    /// the target app and hangs indefinitely when that app is not servicing
    /// Apple Events (observed with Spotify) — it must never run on the main
    /// thread, and a hung probe must not freeze the cache: after 60 s a new
    /// probe may start alongside it, and only the latest probe's answer is
    /// kept.
    private func refreshPermissionCache(running: Set<String>) {
        let now = Date()
        for bundleID in [SpotifySource.bundleID, MusicSource.bundleID] {
            guard running.contains(bundleID) else {
                permissionProbeStarted[bundleID] = nil
                continue
            }
            let due: Bool
            if let started = permissionProbeStarted[bundleID] {
                let age = now.timeIntervalSince(started)
                due = if permissionProbesInFlight.contains(bundleID) {
                    age >= Self.permissionProbeTimeout
                } else {
                    age >= Self.permissionProbeInterval || permissionRecheckRequested.contains(bundleID)
                }
            } else {
                due = true
            }
            guard due else { continue }

            permissionRecheckRequested.remove(bundleID)
            permissionProbeStarted[bundleID] = now
            permissionProbesInFlight.insert(bundleID)
            Task { [weak self] in
                let status = await Task.detached {
                    AutomationPermission.status(towardsBundleID: bundleID)
                }.value
                guard let self, self.permissionProbeStarted[bundleID] == now else { return }
                self.permissionProbesInFlight.remove(bundleID)
                self.permissionCache[bundleID] = status
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
        // every tick would invalidate views even when nothing changed.
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
        if newTrack != track { track = newTrack }

        if let newTrack {
            if newTrack.artworkKey != lastArtworkKey {
                lastArtworkKey = newTrack.artworkKey
                let source = source(for: newTrack.source)
                artworkTask?.cancel()
                artworkTask = Task { [weak self] in
                    let image = await source.fetchArtwork(for: newTrack)
                    guard !Task.isCancelled else { return }
                    self?.artwork = image
                    self?.artworkAccent = image?.averageColor
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
