import SwiftUI

/// "Devices" tab: Mac battery state and sound output with a working
/// volume slider.
struct DevicesModuleView: View {
    var power: PowerSourceMonitor
    var audio: AudioSystemMonitor

    var body: some View {
        HStack(spacing: 10) {
            batteryCard
            soundCard
        }
    }

    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: power.isPlugged ? "bolt.fill" : batterySymbol)
                    .font(Theme.iconFont)
                    .foregroundStyle(power.isPlugged ? Theme.accentPositive : Theme.textPrimary)
                Text("\(power.percent)%")
                    .font(Theme.valueFont)
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(power.isPlugged ? "Charging" : "Battery")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.surfaceRadius))
    }

    private var soundCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(Theme.iconSmallFont)
                    .foregroundStyle(Theme.textPrimary)
                Text(audio.currentDeviceName ?? "Output")
                    .font(Theme.bodyFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.textSecondary)
            }
            Slider(
                value: Binding(
                    get: { audio.volume },
                    set: { audio.setVolume($0) }
                ),
                in: 0...1
            )
            .controlSize(.mini)
            Text("Volume")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.surfaceRadius))
    }

    private var batterySymbol: String {
        switch power.percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}
