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

    init() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func select(_ kind: MediaSourceKind) {
        pinnedSource = kind
        activeSource = kind
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

    private func command(_ operation: @escaping @MainActor (any MediaSource) async -> Void) {
        guard let activeSource, canControl(activeSource) else { return }
        let source = source(for: activeSource)
        Task {
            await operation(source)
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

    private func refresh() async {
        let systemTrack = await system.fetchTrack()
        activeClientBundleID = system.nowPlayingBundleID

        availableSources = await discoverSources()
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
        if spotify.isAvailable(), !sources.contains(.spotify) {
            sources.append(.spotify)
        }
        if music.isAvailable(), !sources.contains(.appleMusic) {
            sources.append(.appleMusic)
        }
        return sources.filter { kind in
            switch kind {
            case .spotify:
                AutomationPermission.status(towardsBundleID: SpotifySource.bundleID) != .denied
            case .appleMusic:
                AutomationPermission.status(towardsBundleID: MusicSource.bundleID) != .denied
            case .client:
                true
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
        if let active = activeSource, !availableSources.contains(active) {
            activeSource = nil
        }

        if let pinned = pinnedSource {
            activeSource = pinned
        } else if activeSource == nil {
            activeSource = playingKind ?? availableSources.first
        } else if let playingKind, playingKind != activeSource, !(track?.isPlaying ?? false) {
            // No explicit pin, the current context is silent and something
            // else is playing — follow the sound.
            activeSource = playingKind
        }
    }

    private func apply(_ newTrack: MediaTrack?) {
        let isPlaying = newTrack?.isPlaying ?? false
        let playbackChanged = isPlaying != wasPlaying
        wasPlaying = isPlaying
        track = newTrack

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
            artwork = nil
            artworkAccent = nil
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
