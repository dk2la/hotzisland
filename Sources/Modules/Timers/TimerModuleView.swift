import SwiftUI

/// "Timer" module, V3: the countdown lives inside a draining accent ring —
/// remaining time is the ring, preset pills and capsule actions beside it.
struct TimerModuleView: View {
    var timer: TimerService

    @State private var customMinutes = ""
    @FocusState private var customFocused: Bool

    private static let ringSize: CGFloat = 158

    var body: some View {
        // Ring plus controls need ~420pt side by side; narrower panels stack
        // them instead of letting the columns spill off the glass.
        GeometryReader { proxy in
            if proxy.size.width < 420 {
                VStack(spacing: 16) {
                    countdownRing
                    controls
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .center, spacing: 28) {
                    countdownRing
                    controls
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// The ring holds what is LEFT and drains clockwise from 12 o'clock —
    /// a glance reads like a hardware egg timer.
    private var countdownRing: some View {
        let remaining = timer.duration > 0 ? timer.remaining / timer.duration : 0
        return ZStack {
            Circle()
                .stroke(Theme.segmentOff, lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0, min(1, remaining)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Scoped to `duration`: picking a preset sweeps the arc, the
                // per-second ticks (`remaining`) still jump — instrument rule.
                .animation(.easeOut(duration: 0.2), value: timer.duration)
            VStack(spacing: 4) {
                InstrumentLabel(L10n.t(timer.isRunning ? .focusRunning : .focusReady))
                Text(TimeFormat.mmss(timer.remaining))
                    .font(Theme.timerFont)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
    }

    private var controls: some View {
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
                customKey
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

    /// Fifth key in the preset row: type any minute count, Enter arms it.
    /// Lights up like an active preset while a non-preset duration is set.
    private var customKey: some View {
        let isCustomActive = !TimerService.presets.contains(timer.duration)
        return TextField(L10n.t(.timerCustomPlaceholder), text: $customMinutes)
            .textFieldStyle(.plain)
            .font(Theme.subFont)
            .fontWeight(.medium)
            .kerning(0.3)
            .multilineTextAlignment(.center)
            .foregroundStyle(isCustomActive ? Theme.textPrimary : Theme.textSecondary)
            .focused($customFocused)
            .onSubmit(applyCustomMinutes)
            .onChange(of: customMinutes) { _, value in
                let digits = String(value.filter(\.isNumber).prefix(3))
                if digits != value { customMinutes = digits }
            }
            .frame(width: 34)
            .padding(.vertical, 7)
            .background(
                isCustomActive ? Theme.raisedFill : Theme.raisedFill.opacity(0.75),
                in: Capsule()
            )
            .overlay(Capsule().stroke(isCustomActive ? Theme.accentBorder : .clear, lineWidth: 1))
            .opacity(timer.isRunning ? 0.35 : 1)
            .disabled(timer.isRunning)
    }

    private func applyCustomMinutes() {
        guard let minutes = Int(customMinutes), minutes >= 1 else { return }
        timer.setDuration(TimeInterval(min(minutes, 999) * 60))
        customFocused = false
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
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
    }
}
