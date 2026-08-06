import SwiftUI

/// Closed-island playback indicator: mini artwork on the left of the notch,
/// remaining time on the right — iOS Dynamic Island style.
struct CompactMediaView: View {
    let track: MediaTrack
    let artwork: NSImage?

    var body: some View {
        HStack {
            artworkThumb
            Spacer(minLength: 0)
            Text("-" + TimeFormat.mmss(track.duration - track.position))
                .font(Theme.smallValueFont.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var artworkThumb: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Theme.surface
                    Image(systemName: "music.note")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
