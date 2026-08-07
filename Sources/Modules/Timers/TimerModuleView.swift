import SwiftUI

/// "Timer" tab: countdown with presets. While running, the closed island
/// shows the remaining time in compact form.
struct TimerModuleView: View {
    var timer: TimerService

    var body: some View {
        VStack(spacing: 10) {
            Text(TimeFormat.mmss(timer.remaining))
                .font(Theme.timerFont)
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(countsDown: true))
                .animation(.linear(duration: 0.3), value: timer.remaining)

            HStack(spacing: 6) {
                ForEach(TimerService.presets, id: \.self) { preset in
                    presetChip(preset)
                }
            }

            HStack(spacing: 18) {
                controlButton(timer.isRunning ? "pause.fill" : "play.fill") {
                    timer.isRunning ? timer.pause() : timer.start()
                }
                controlButton("arrow.counterclockwise") {
                    timer.reset()
                }
            }
        }
    }

    private func presetChip(_ preset: TimeInterval) -> some View {
        let isActive = timer.duration == preset
        return Button {
            timer.setDuration(preset)
        } label: {
            Text("\(Int(preset / 60))m")
                .font(Theme.captionFont)
                .foregroundStyle(isActive ? Theme.islandFill : Theme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(isActive ? Theme.textPrimary : Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .opacity(timer.isRunning ? 0.4 : 1)
        .disabled(timer.isRunning)
    }

    private func controlButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.iconFont)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 34, height: 28)
                .background(Theme.surface, in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Closed-island indicator while the timer runs.
struct CompactTimerView: View {
    var timer: TimerService

    var body: some View {
        HStack {
            Image(systemName: "timer")
                .font(Theme.iconSmallFont)
                .foregroundStyle(Theme.accentWarning)
            Spacer(minLength: 0)
            Text(TimeFormat.mmss(timer.remaining))
                .font(Theme.smallValueFont.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
    }
}
