import SwiftUI

/// "System" module, V3: stat rows on raised glass — label left, value right,
/// a thin severity bar underneath — plus a volume row. Values jump.
struct MetricsModuleView: View {
    var stats: SystemStatsService
    var power: PowerSourceMonitor
    var audio: AudioSystemMonitor

    var body: some View {
        VStack(spacing: 6) {
            statRow(label: "CPU", value: percentText(stats.cpuUsage), fraction: stats.cpuUsage)
            statRow(
                label: L10n.t(.sysMemory),
                value: percentText(memoryFraction),
                fraction: memoryFraction
            )
            statRow(label: L10n.t(.sysNetwork), value: netText, fraction: nil)
            powerRow
            volumeRow
            Spacer(minLength: 0)
        }
    }

    private var memoryFraction: Double {
        stats.memoryTotal > 0 ? Double(stats.memoryUsed) / Double(stats.memoryTotal) : 0
    }

    private func percentText(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private var netText: String {
        "↓ \(Self.rate(stats.downloadRate))  ↑ \(Self.rate(stats.uploadRate))"
    }

    // MARK: - Rows

    private func statRow(label: String, value: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary.opacity(0.95))
            }
            if let fraction {
                GlassProgressBar(fraction: fraction, fillColor: Theme.severity(fraction))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var powerRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Text(L10n.t(.sysBattery))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    if power.isPlugged {
                        HStack(spacing: 4) {
                            BlinkingDot(size: 5)
                            Text(L10n.t(.sysCharging))
                                .font(Theme.subFont)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                Spacer(minLength: 8)
                Text("\(power.percent)%")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary.opacity(0.95))
            }
            GlassProgressBar(fraction: Double(power.percent) / 100)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var volumeRow: some View {
        HStack(spacing: 12) {
            Text(L10n.t(.sysVolume))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Slider(
                value: Binding(
                    get: { audio.volume },
                    set: { audio.setVolume($0) }
                ),
                in: 0...1
            )
            .controlSize(.mini)
            Text("\(Int(audio.volume * 100))")
                .font(Theme.readoutSFont)
                .foregroundStyle(Theme.textPrimary.opacity(0.9))
                .frame(width: 26, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Formatting

    private static func rate(_ rate: Double) -> String {
        switch rate {
        case ..<1_000: "0 KB/s"
        case ..<1_000_000: String(format: "%.0f KB/s", rate / 1_000)
        case ..<1_000_000_000: String(format: "%.1f MB/s", rate / 1_000_000)
        default: String(format: "%.1f GB/s", rate / 1_000_000_000)
        }
    }
}
