import SwiftUI

/// Playbooks: one press of ▶ and a tiny desktop does the work — the apps
/// open, the windows snap into three columns, Focus comes on and the
/// timer starts — while the step lights below tick off one by one.
struct PlaybooksStage: View {
    @State private var running = false
    @State private var pressed = false
    @State private var appsShown = 0
    @State private var arranged = false
    @State private var focusOn = false
    @State private var timerShown = false
    @State private var seconds = 25 * 60
    @State private var stepsDone = 0
    @State private var done = false

    private static let steps = ["macwindow.on.rectangle", WindowLayout.thirds.icon, "moon.fill", "timer"]
    private static let windowColors = [StagePalette.blue, StagePalette.orange, StagePalette.teal]

    var body: some View {
        StagePanel(title: NotchTab.playbooks.title) {
            StageGlyph("plus")
        } content: {
            VStack(spacing: 6) {
                card(
                    icon: "sunrise.fill",
                    name: L10n.t(.obMockPlaybook1),
                    summary: [
                        L10n.f(.playApps, 3), WindowLayout.thirds.title,
                        L10n.t(.playFocus), L10n.f(.ageMin, 25),
                    ].joined(separator: " · "),
                    live: true
                )
                card(
                    icon: "brain.head.profile",
                    name: L10n.t(.obMockPlaybook2),
                    summary: [
                        L10n.t(.playCloseRest), L10n.t(.playFocus), L10n.f(.ageMin, 50),
                    ].joined(separator: " · "),
                    live: false
                )
                desktop
                    .padding(.top, 6)
                stepLights
                    .padding(.top, 4)
            }
        }
        .storyboard(finalFrame: {
            appsShown = 3
            arranged = true
            focusOn = true
            timerShown = true
            stepsDone = Self.steps.count
            done = true
        }, loop: play)
    }

    private func card(icon: String, name: String, summary: String, live: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raisedFill))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Theme.bodyFont)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(Theme.textPrimary)
                Text(summary)
                    .font(Theme.subFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            if live, done {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
            StageButton(systemName: "play.fill", solid: live && running, pressed: live && pressed)
                .opacity(running && !live ? 0.5 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            live && running ? Theme.raisedFill.opacity(0.7) : Theme.cardFill,
            in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
        )
        .animation(.easeOut(duration: 0.15), value: running)
        .animation(.easeOut(duration: 0.2), value: done)
    }

    // MARK: - Desktop

    /// A miniature screen: menu bar on top (Focus moon, timer readout),
    /// three app windows below.
    private var desktop: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach([14, 10, 12], id: \.self) { width in
                    Capsule().fill(Theme.textPrimary.opacity(0.18)).frame(width: CGFloat(width), height: 3)
                }
                Spacer(minLength: 0)
                if focusOn {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
                if timerShown {
                    Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                        .font(Theme.mono(8, .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 14)
            .background(Theme.textPrimary.opacity(0.06))
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ForEach(0..<3, id: \.self) { index in
                        let frame = windowFrame(index, in: proxy.size)
                        MiniWindow(color: Self.windowColors[index])
                            .frame(width: frame.width, height: frame.height)
                            .rotationEffect(.degrees(arranged ? 0 : [-4, 3, -2][index]))
                            .offset(x: frame.minX, y: frame.minY)
                            .opacity(index < appsShown ? 1 : 0)
                            .scaleEffect(index < appsShown ? 1 : 0.6)
                    }
                }
            }
            .padding(5)
        }
        .frame(height: 112)
        .background(shape.fill(Color.black.opacity(0.35)))
        .overlay(shape.stroke(Theme.hairline, lineWidth: 1))
        .clipShape(shape)
    }

    /// Scattered as apps open them, then the "three columns" layout.
    private func windowFrame(_ index: Int, in size: CGSize) -> CGRect {
        if arranged {
            let gap: CGFloat = 4
            let width = (size.width - 2 * gap) / 3
            return CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: size.height)
        }
        let scattered: [CGRect] = [
            CGRect(x: 0.06, y: 0.16, width: 0.42, height: 0.66),
            CGRect(x: 0.46, y: 0.30, width: 0.46, height: 0.62),
            CGRect(x: 0.26, y: 0.02, width: 0.38, height: 0.70),
        ]
        let unit = scattered[index]
        return CGRect(
            x: unit.minX * size.width, y: unit.minY * size.height,
            width: unit.width * size.width, height: unit.height * size.height
        )
    }

    /// One light per step: dim → accent ring while running → accent wash.
    private var stepLights: some View {
        HStack(spacing: 6) {
            ForEach(Self.steps.indices, id: \.self) { index in
                let isDone = index < stepsDone
                let isActive = running && index == stepsDone
                let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
                Image(systemName: Self.steps[index])
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isDone || isActive ? Theme.accent : Theme.textFaint)
                    .frame(width: 26, height: 22)
                    .background(shape.fill(isDone ? Theme.accentWash : Theme.cardFill))
                    .overlay(shape.stroke(Theme.accentBorder, lineWidth: 1).opacity(isActive ? 1 : 0))
                    .animation(.easeOut(duration: 0.2), value: stepsDone)
            }
            Spacer(minLength: 0)
            Text("\(stepsDone)/\(Self.steps.count)")
                .font(Theme.readoutSFont)
                .foregroundStyle(stepsDone == Self.steps.count ? Theme.accent : Theme.textQuaternary)
        }
    }

    private func play() async -> Bool {
        guard await beat(0.9) else { return false }
        pressed = true
        guard await beat(0.12) else { return false }
        pressed = false
        running = true
        guard await beat(0.3) else { return false }
        for index in 1...3 {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { appsShown = index }
            guard await beat(0.16) else { return false }
        }
        guard await beat(0.25) else { return false }
        stepsDone = 1
        guard await beat(0.35) else { return false }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { arranged = true }
        guard await beat(0.6) else { return false }
        stepsDone = 2
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { focusOn = true }
        guard await beat(0.5) else { return false }
        stepsDone = 3
        withAnimation(.easeOut(duration: 0.2)) { timerShown = true }
        guard await beat(0.4) else { return false }
        stepsDone = 4
        running = false
        done = true
        // The timer readout jumps, as instruments do.
        for _ in 0..<2 {
            guard await beat(1.0) else { return false }
            seconds -= 1
        }
        guard await beat(1.4) else { return false }
        withAnimation(.easeIn(duration: 0.3)) {
            appsShown = 0
            focusOn = false
            timerShown = false
            done = false
        }
        guard await beat(0.35) else { return false }
        arranged = false
        stepsDone = 0
        seconds = 25 * 60
        return await beat(0.4)
    }
}

/// An app window in miniature: tinted title bar with traffic lights, a few
/// lines of skeleton content.
private struct MiniWindow: View {
    let color: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.white.opacity(0.55)).frame(width: 3, height: 3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(height: 9)
            .background(color.opacity(0.85))
            VStack(alignment: .leading, spacing: 3) {
                ForEach([0.8, 0.55, 0.7], id: \.self) { fraction in
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Theme.textPrimary.opacity(0.14))
                            .frame(width: proxy.size.width * fraction, height: 3)
                    }
                    .frame(height: 3)
                }
            }
            .padding(.horizontal, 5)
            Spacer(minLength: 0)
        }
        .background(shape.fill(Color(white: 0.15)))
        .overlay(shape.stroke(Color.white.opacity(0.1), lineWidth: 1))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }
}
