import SwiftUI

/// Compact event presentation: instrument caption on the left of the notch,
/// mono readout on the right (the middle is the camera housing).
struct LiveEventView: View {
    let event: LiveEvent

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: NotchMetrics.eventSideWidth - 24, alignment: .leading)
            Spacer(minLength: 0)
            trailing
                .frame(width: NotchMetrics.eventSideWidth - 24, alignment: .trailing)
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var leading: some View {
        switch event {
        case .charging(_, let plugged):
            HStack(spacing: 6) {
                if plugged {
                    BlinkingDot(size: 5)
                } else {
                    Circle().fill(Theme.segmentOff).frame(width: 5, height: 5)
                }
                InstrumentLabel("pwr", color: plugged ? Theme.amber : Theme.textQuaternary)
            }
        case .audioDevice:
            HStack(spacing: 6) {
                Circle().fill(Theme.amber).frame(width: 5, height: 5)
                InstrumentLabel("out", color: Theme.amber)
            }
        case .volume:
            InstrumentLabel("vol", color: Theme.textPrimary.opacity(0.45))
        case .timerFinished:
            HStack(spacing: 6) {
                BlinkingDot(size: 5)
                InstrumentLabel("timer", color: Theme.amber)
            }
        case .playbookRan:
            HStack(spacing: 6) {
                BlinkingDot(size: 5)
                InstrumentLabel("run", color: Theme.amber)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch event {
        case .charging(let percent, let plugged):
            Text(plugged ? "\(percent)% charging" : "\(percent)%")
                .font(Theme.readoutSFont)
                .foregroundStyle(plugged ? Theme.amber : Theme.textPrimary.opacity(0.8))
                .lineLimit(1)
        case .audioDevice(let name):
            Text(name)
                .font(Theme.readoutSFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
        case .volume(let level):
            HStack(spacing: 6) {
                SegmentBar(fraction: level, segments: 8, fillColor: Theme.textPrimary.opacity(0.7))
                    .frame(width: 48)
                Text("\(Int(level * 100))")
                    .font(Theme.readoutSFont)
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
                    .frame(width: 20, alignment: .trailing)
            }
        case .timerFinished:
            Text("done")
                .font(Theme.readoutSFont)
                .foregroundStyle(Theme.amber)
        case .playbookRan(let name):
            Text(name)
                .font(Theme.readoutSFont)
                .lineLimit(1)
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
        }
    }
}
