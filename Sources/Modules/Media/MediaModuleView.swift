import SwiftUI

/// "Music" module, V3: artwork tile, SF titles, thin progress with a knob,
/// circular glass transport with a solid-white play button.
struct MediaModuleView: View {
    var media: MediaCenter

    var body: some View {
        if let track = media.track {
            HStack(alignment: .center, spacing: 16) {
                artworkView
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(track.title)
                            .font(Theme.titleFont)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 12)
                        sourceTag
                    }
                    if !track.artist.isEmpty {
                        Text(track.artist)
                            .font(Theme.subFont)
                            .lineLimit(1)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 2)
                    }
                    ScrubberBar(
                        fraction: track.duration > 0 ? track.position / track.duration : 0
                    ) { target in
                        media.seek(toFraction: target)
                    }
                    .disabled(!media.canControlActive)
                    .padding(.top, 8)
                    HStack {
                        Text(TimeFormat.mmss(track.position))
                        Spacer()
                        Text("−" + TimeFormat.mmss(track.duration - track.position))
                    }
                    .font(Theme.readoutSFont)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 5)
                    transport(for: track)
                        .padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                if media.availableSources.count > 1 {
                    sourceSwitcher
                }
                EmptyStateZone(label: L10n.t(.mediaNoSignal), sublabel: idleMessage)
                    .frame(maxHeight: 110)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var artworkView: some View {
        Group {
            if let artwork = media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Theme.raisedFill
                    Image(systemName: "music.note")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// Source chip — a capsule with a status dot; tap to switch when several
    /// players are around.
    @ViewBuilder
    private var sourceTag: some View {
        if media.availableSources.count > 1 {
            sourceSwitcher
        } else if let active = media.activeSource {
            tagView(for: active, isActive: true)
        }
    }

    private var sourceSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(media.availableSources) { kind in
                Button {
                    media.select(kind)
                } label: {
                    tagView(for: kind, isActive: media.activeSource == kind)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func tagView(for kind: MediaSourceKind, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? Theme.accent : Theme.segmentOff)
                .frame(width: 5, height: 5)
            InstrumentLabel(
                media.label(for: kind),
                color: isActive ? Theme.accent : Theme.textQuaternary
            )
        }
    }

    private func transport(for track: MediaTrack) -> some View {
        HStack(spacing: 8) {
            CircleGlassButton(systemName: "backward.fill", size: 30) { media.previous() }
                .disabled(!media.canControlActive)
            CircleGlassButton(
                systemName: track.isPlaying ? "pause.fill" : "play.fill",
                size: 36,
                solid: true
            ) {
                media.togglePlayPause()
            }
            .disabled(!media.canControlActive)
            CircleGlassButton(systemName: "forward.fill", size: 30) { media.next() }
                .disabled(!media.canControlActive)
            Spacer(minLength: 0)
            if media.supportsLike {
                CircleGlassButton(systemName: "heart", size: 30) { media.like() }
                    .disabled(!media.canControlActive)
            }
        }
        .opacity(media.canControlActive ? 1 : 0.4)
    }

    private var idleMessage: String {
        if let active = media.activeSource, !media.canControl(active) {
            return L10n.f(.mediaSilent, media.label(for: active))
        }
        return L10n.t(.mediaIdle)
    }
}
