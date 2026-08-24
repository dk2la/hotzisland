import SwiftUI

/// "Timer" module, V3: tracked caption, big SF countdown over a thin
/// progress track, preset pills and capsule actions.
struct TimerModuleView: View {
    var timer: TimerService

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 0) {
                InstrumentLabel(L10n.t(timer.isRunning ? .focusRunning : .focusReady))
                Text(TimeFormat.mmss(timer.remaining))
                    .font(Theme.timerFont)
                    .foregroundStyle(Theme.textPrimary.opacity(0.97))
                    .padding(.top, 2)
                SegmentBar(
                    fraction: timer.duration > 0
                        ? 1 - timer.remaining / timer.duration
                        : 0,
                    segments: 10,
                    fillColor: Theme.accent
                )
                .frame(width: 190)
                .padding(.top, 10)
            }
            .fixedSize()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(TimerService.presets, id: \.self) { preset in
                        KeyButton(
                            label: String(format: "%02d", Int(preset / 60)),
                            isActive: timer.duration == preset,
                            enabled: !timer.isRunning
                        ) {
                            timer.setDuration(preset)
                        }
                    }
                }
                HStack(spacing: 8) {
                    GlassCapsuleButton(
                        label: L10n.t(timer.isRunning ? .timerPause : .timerStart),
                        isPrimary: true
                    ) {
                        timer.isRunning ? timer.pause() : timer.start()
                    }
                    GlassCapsuleButton(label: L10n.t(.timerReset)) {
                        timer.reset()
                    }
                }
                .padding(.top, 14)
                InstrumentLabel(L10n.t(.timerDoneNote), color: Theme.textFaint)
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Closed-island indicator while the timer runs: blinking dot, countdown.
struct CompactTimerView: View {
    var timer: TimerService

    var body: some View {
        HStack {
            BlinkingDot(size: 6)
            Spacer(minLength: 0)
            Text(TimeFormat.mmss(timer.remaining))
                .font(Theme.smallValueFont)
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
        }
        .padding(.horizontal, 14)
    }
}
