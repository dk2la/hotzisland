import SwiftUI

/// "Media" tab of the expanded panel: artwork, track info, transport
/// controls and playback-context switching.
struct MediaModuleView: View {
    var media: MediaCenter

    var body: some View {
        if let track = media.track {
            HStack(spacing: 14) {
                artworkView
                VStack(alignment: .leading, spacing: 5) {
                    if media.availableSources.count > 1 {
                        sourceChips
                    }
                    Text(track.title)
                        .font(Theme.headlineFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.textPrimary)
                    if !track.artist.isEmpty {
                        Text(track.artist)
                            .font(Theme.captionFont)
                            .lineLimit(1)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    progress(for: track)
                    controls
                }
            }
        } else {
            VStack(spacing: 8) {
                if media.availableSources.count > 1 {
                    sourceChips
                }
                Image(systemName: "music.note")
                    .font(Theme.iconLargeFont)
                    .foregroundStyle(Theme.textQuaternary)
                Text(idleMessage)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textQuaternary)
            }
        }
    }

    /// An inactive browser context cannot be queried — say so instead of
    /// pretending nothing is playing.
    private var idleMessage: String {
        if let active = media.activeSource, !media.canControl(active) {
            return "\(media.label(for: active)) is idle"
        }
        return "Nothing playing"
    }

    private var artworkView: some View {
        Group {
            if let artwork = media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Theme.surface
                    Image(systemName: "music.note")
                        .font(Theme.iconLargeFont)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: Theme.surfaceRadius))
    }

    private var sourceChips: some View {
        HStack(spacing: 6) {
            ForEach(media.availableSources) { kind in
                Button {
                    media.select(kind)
                } label: {
                    Text(media.label(for: kind))
                        .font(Theme.captionFont)
                        .foregroundStyle(media.activeSource == kind ? Theme.islandFill : Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            media.activeSource == kind ? Theme.textPrimary : Theme.surface,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func progress(for track: MediaTrack) -> some View {
        VStack(spacing: 3) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(Theme.textPrimary)
                        .frame(width: track.duration > 0
                            ? geometry.size.width * min(1, track.position / track.duration)
                            : 0)
                }
            }
            .frame(height: 3)
            HStack {
                Text(TimeFormat.mmss(track.position))
                Spacer()
                Text("-" + TimeFormat.mmss(track.duration - track.position))
            }
            .font(Theme.captionFont.monospacedDigit())
            .foregroundStyle(Theme.textTertiary)
        }
    }

    private var controls: some View {
        HStack(spacing: 22) {
            transportButton("backward.fill") { media.previous() }
            transportButton(media.track?.isPlaying == true ? "pause.fill" : "play.fill", size: 18) {
                media.togglePlayPause()
            }
            transportButton("forward.fill") { media.next() }
            Spacer()
            if media.supportsLike {
                transportButton("heart") { media.like() }
            }
        }
        .opacity(media.canControlActive ? 1 : 0.35)
        .disabled(!media.canControlActive)
    }

    private func transportButton(
        _ symbol: String,
        size: CGFloat = 13,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.iconFont(size: size))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
