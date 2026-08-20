import SwiftUI

/// "Timer" channel: big mono readout with a segmented progress strip on the
/// left, mechanical preset keys and controls on the right.
struct TimerModuleView: View {
    var timer: TimerService

    var body: some View {
        HStack(alignment: .center, spacing: 26) {
            VStack(alignment: .leading, spacing: 0) {
                Text(TimeFormat.mmss(timer.remaining))
                    .font(Theme.timerFont)
                    .foregroundStyle(Theme.textPrimary)
                SegmentBar(
                    fraction: timer.duration > 0
                        ? 1 - timer.remaining / timer.duration
                        : 0,
                    segments: 10,
                    fillColor: Theme.accent
                )
                .padding(.top, 10)
                InstrumentLabel("pomodoro · wall-clock")
                    .padding(.top, 8)
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
                    primaryButton(timer.isRunning ? "Пауза" : "Старт") {
                        timer.isRunning ? timer.pause() : timer.start()
                    }
                    secondaryButton("Сброс") {
                        timer.reset()
                    }
                }
                .padding(.top, 14)
                InstrumentLabel("done → live-event + sound", color: Theme.textFaint)
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.headlineFont)
                .foregroundStyle(Color(red: 0.043, green: 0.043, blue: 0.039))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.textPrimary.opacity(0.22), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Closed-island indicator while the timer runs: blinking amber dot,
/// mono countdown.
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
