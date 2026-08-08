import SwiftUI

/// Compact event presentation: content sits on both sides of the physical
/// notch (the middle of the island is the camera housing — nothing can be
/// drawn there).
struct LiveEventView: View {
    let event: LiveEvent

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: NotchMetrics.eventSideWidth - 24)
            Spacer(minLength: 0)
            trailing
                .frame(width: NotchMetrics.eventSideWidth - 24)
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var leading: some View {
        switch event {
        case .charging(_, let plugged):
            Image(systemName: plugged ? "bolt.fill" : "powerplug.fill")
                .font(Theme.iconFont)
                .foregroundStyle(plugged ? Theme.accentPositive : Theme.iconMuted)
        case .audioDevice(let name):
            Image(systemName: name.localizedCaseInsensitiveContains("airpods") ? "airpods" : "headphones")
                .font(Theme.iconFont)
                .foregroundStyle(Theme.textPrimary)
        case .volume(let level):
            Image(systemName: level <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(Theme.tabIconFont)
                .foregroundStyle(Theme.textPrimary)
        case .timerFinished:
            Image(systemName: "timer")
                .font(Theme.iconFont)
                .foregroundStyle(Theme.accentWarning)
        case .playbookRan:
            Image(systemName: "bolt.fill")
                .font(Theme.iconFont)
                .foregroundStyle(Theme.accentPositive)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch event {
        case .charging(let percent, let plugged):
            Text("\(percent)%")
                .font(Theme.smallValueFont)
                .foregroundStyle(plugged ? Theme.accentPositive : Theme.textPrimary)
        case .audioDevice(let name):
            Text(name)
                .font(Theme.bodyFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Theme.textSecondary)
        case .volume(let level):
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(Theme.textPrimary)
                    .frame(width: max(0, 58 * level))
            }
            .frame(width: 58, height: 4)
        case .timerFinished:
            Text("Done!")
                .font(Theme.smallValueFont)
                .foregroundStyle(Theme.accentWarning)
        case .playbookRan(let name):
            Text(name)
                .font(Theme.smallValueFont)
                .lineLimit(1)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
