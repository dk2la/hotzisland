import SwiftUI

/// "Sys" channel: a 4-cell instrument grid (CPU · MEM · NET · PWR), a CPU
/// history strip and a volume register. Battery and audio moved here from
/// the removed Devices tab, per the Instrument DS.
struct MetricsModuleView: View {
    var stats: SystemStatsService
    var power: PowerSourceMonitor
    var audio: AudioSystemMonitor

    var body: some View {
        VStack(spacing: 8) {
            instrumentGrid
            historyStrip
            volumeRegister
            Spacer(minLength: 0)
        }
    }

    // MARK: - Instrument cells

    private var instrumentGrid: some View {
        HStack(spacing: 1) {
            percentCell(label: "CPU", fraction: stats.cpuUsage)
            percentCell(
                label: "MEM",
                fraction: stats.memoryTotal > 0
                    ? Double(stats.memoryUsed) / Double(stats.memoryTotal)
                    : 0
            )
            netCell
            powerCell
        }
        .background(Theme.hairlineSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.hairlineSoft, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func percentCell(label: String, fraction: Double) -> some View {
        cell {
            InstrumentLabel(label)
            readout(percent: fraction)
            SegmentBar(fraction: fraction, segments: 8)
        }
    }

    private var netCell: some View {
        cell {
            InstrumentLabel("NET")
            rateRow("↓", stats.downloadRate)
            rateRow("↑", stats.uploadRate)
        }
    }

    private var powerCell: some View {
        cell {
            InstrumentLabel("PWR")
            readout(percent: Double(power.percent) / 100, colored: false)
            HStack(spacing: 6) {
                if power.isPlugged {
                    BlinkingDot(size: 5)
                    InstrumentLabel("charging", color: Theme.textPrimary.opacity(0.45))
                } else {
                    Circle()
                        .fill(Theme.segmentOff)
                        .frame(width: 5, height: 5)
                    InstrumentLabel("battery", color: Theme.textPrimary.opacity(0.45))
                }
            }
        }
    }

    private func cell(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardFill)
    }

    private func readout(percent fraction: Double, colored: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(Int((fraction * 100).rounded()))")
                .font(Theme.readoutLFont)
                .foregroundStyle(colored ? Theme.severity(fraction) : Theme.textPrimary)
            Text("%")
                .font(Theme.readoutSFont)
                .foregroundStyle(Theme.textFaint)
        }
    }

    private func rateRow(_ arrow: String, _ rate: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(arrow) \(Self.rateValue(rate))")
                .font(Theme.readoutMFont)
                .foregroundStyle(Theme.textPrimary)
            Text(Self.rateUnit(rate))
                .font(Theme.readoutSFont)
                .foregroundStyle(Theme.textFaint)
        }
    }

    // MARK: - History

    /// Last 16 CPU samples as an instrument bar strip. Bars jump — data is
    /// never animated.
    private var historyStrip: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(stats.cpuHistory.enumerated()), id: \.offset) { _, sample in
                Rectangle()
                    .fill(sample >= 0.85 ? Theme.critical : (sample >= 0.6 ? Theme.amber : Theme.textPrimary.opacity(0.25)))
                    .frame(height: max(2, 36 * sample))
            }
            if stats.cpuHistory.isEmpty {
                Rectangle().fill(.clear).frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .bottom)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.hairlineSoft, lineWidth: 1)
        )
    }

    // MARK: - Volume

    private var volumeRegister: some View {
        HStack(spacing: 12) {
            InstrumentLabel("VOL")
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
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 26, alignment: .trailing)
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Formatting

    private static func rateValue(_ rate: Double) -> String {
        switch rate {
        case ..<1_000: "0"
        case ..<1_000_000: String(format: "%.0f", rate / 1_000)
        case ..<1_000_000_000: String(format: "%.1f", rate / 1_000_000)
        default: String(format: "%.1f", rate / 1_000_000_000)
        }
    }

    private static func rateUnit(_ rate: Double) -> String {
        switch rate {
        case ..<1_000_000: "KB/s"
        case ..<1_000_000_000: "MB/s"
        default: "GB/s"
        }
    }
}
