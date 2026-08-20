import SwiftUI

/// Closed-island playback indicator: amber dot while playing (dim when
/// paused), mono remaining time on the right.
struct CompactMediaView: View {
    let track: MediaTrack
    let artwork: NSImage?

    var body: some View {
        HStack {
            Circle()
                .fill(track.isPlaying ? Theme.accent : Theme.segmentOff)
                .frame(width: 6, height: 6)
            Spacer(minLength: 0)
            Text("−" + TimeFormat.mmss(track.duration - track.position))
                .font(Theme.smallValueFont)
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
        }
        .padding(.horizontal, 14)
    }
}
