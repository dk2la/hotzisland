import SwiftUI

/// "System" tab: CPU, memory and network at a glance.
struct MetricsModuleView: View {
    var stats: SystemStatsService

    var body: some View {
        HStack(spacing: 10) {
            cpuCard
            memoryCard
            networkCard
        }
    }

    private var cpuCard: some View {
        card(title: "CPU") {
            Text("\(Int(stats.cpuUsage * 100))%")
                .font(Theme.valueFont)
                .foregroundStyle(Theme.textPrimary)
            bar(fraction: stats.cpuUsage, color: severityColor(stats.cpuUsage))
        }
    }

    private var memoryCard: some View {
        let fraction = stats.memoryTotal > 0
            ? Double(stats.memoryUsed) / Double(stats.memoryTotal)
            : 0
        return card(title: "Memory") {
            Text(memoryLabel)
                .font(Theme.headlineFont.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            bar(fraction: fraction, color: severityColor(fraction))
        }
    }

    private var networkCard: some View {
        card(title: "Network") {
            VStack(alignment: .leading, spacing: 2) {
                rateRow(symbol: "arrow.down", rate: stats.downloadRate)
                rateRow(symbol: "arrow.up", rate: stats.uploadRate)
            }
        }
    }

    // MARK: - Pieces

    private func card(
        title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
            Spacer(minLength: 0)
            Text(title)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.surfaceRadius))
    }

    private func bar(fraction: Double, color: Color) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.track)
            GeometryReader { geometry in
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 4)
        .animation(Theme.eventSpring, value: fraction)
    }

    private func rateRow(symbol: String, rate: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textTertiary)
            Text(Self.format(rate: rate))
                .font(Theme.headlineFont.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var memoryLabel: String {
        let used = Double(stats.memoryUsed) / 1_073_741_824
        let total = Double(stats.memoryTotal) / 1_073_741_824
        return String(format: "%.1f / %.0f GB", used, total)
    }

    private func severityColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: Theme.textPrimary
        case ..<0.85: Theme.accentWarning
        default: Theme.accentCritical
        }
    }

    private static func format(rate: Double) -> String {
        switch rate {
        case ..<1_000: "0 KB/s"
        case ..<1_000_000: String(format: "%.0f KB/s", rate / 1_000)
        case ..<1_000_000_000: String(format: "%.1f MB/s", rate / 1_000_000)
        default: String(format: "%.1f GB/s", rate / 1_000_000_000)
        }
    }
}
