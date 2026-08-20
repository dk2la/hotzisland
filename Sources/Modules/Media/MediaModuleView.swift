import SwiftUI

/// "Media" channel: tape-deck aesthetic — bordered artwork, amber source
/// tag, segmented progress and mechanical transport keys.
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
                            .padding(.top, 3)
                    }
                    SegmentBar(
                        fraction: track.duration > 0 ? track.position / track.duration : 0,
                        segments: 15,
                        fillColor: Theme.accent
                    )
                    .padding(.top, 14)
                    HStack {
                        Text(TimeFormat.mmss(track.position))
                        Spacer()
                        Text("−" + TimeFormat.mmss(track.duration - track.position))
                    }
                    .font(Theme.readoutSFont)
                    .foregroundStyle(Theme.textQuaternary)
                    .padding(.top, 7)
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
                DashedZone(label: "no signal", sublabel: idleMessage)
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
                    Theme.cardFill
                    InstrumentLabel("no art")
                }
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.islandBorder, lineWidth: 1)
        )
    }

    /// "● spotify" — amber when the context is controllable, dim otherwise.
    @ViewBuilder
    private var sourceTag: some View {
        if media.availableSources.count > 1 {
            sourceSwitcher
        } else if let active = media.activeSource {
            tagView(for: active, isActive: true)
        }
    }

    private var sourceSwitcher: some View {
        HStack(spacing: 10) {
            ForEach(media.availableSources) { kind in
                Button {
                    media.select(kind)
                } label: {
                    tagView(for: kind, isActive: media.activeSource == kind)
                        .contentShape(Rectangle())
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
            KeyButton(label: "◀◀", enabled: media.canControlActive) { media.previous() }
            KeyButton(
                label: track.isPlaying ? "❚❚" : "▶",
                isPrimary: true,
                enabled: media.canControlActive
            ) {
                media.togglePlayPause()
            }
            KeyButton(label: "▶▶", enabled: media.canControlActive) { media.next() }
            Spacer(minLength: 0)
            if media.supportsLike {
                KeyButton(label: "LIKE", enabled: media.canControlActive) { media.like() }
            }
        }
    }

    private var idleMessage: String {
        if let active = media.activeSource, !media.canControl(active) {
            return "\(media.label(for: active)) молчит"
        }
        return "Ничего не играет"
    }
}
