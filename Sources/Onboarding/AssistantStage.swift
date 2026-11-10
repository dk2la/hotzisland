import SwiftUI

/// Assistant: a question types itself and goes out, the assistant thinks,
/// calls the calendar tool, and the answer streams in — then reads it out
/// loud, the voice glyph lit.
struct AssistantStage: View {
    @State private var askTyped = 0
    @State private var sent = false
    @State private var sendPressed = false
    @State private var thinking = false
    @State private var toolShown = false
    @State private var answerShown = 0
    @State private var speaking = false

    private var ask: TypedText { TypedText(L10n.t(.obMockAsk), byWord: false) }
    private var answer: TypedText { TypedText(L10n.t(.obMockAnswer)) }

    var body: some View {
        StagePanel(title: ModuleTab.assistant.title) {
            StageGlyph("waveform", active: speaking)
                .symbolEffect(.variableColor.iterative, isActive: speaking)
            StageGlyph("trash")
        } content: {
            VStack(spacing: 8) {
                if sent {
                    HStack {
                        Spacer(minLength: 40)
                        bubble(L10n.t(.obMockAsk), color: Theme.textPrimary, fill: Theme.raisedFill.opacity(0.8))
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if toolShown {
                    HStack {
                        Text("⚙ events_on(tomorrow)")
                            .font(Theme.readoutSFont)
                            .foregroundStyle(Theme.textQuaternary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                    .transition(.opacity)
                }
                if thinking {
                    HStack(spacing: 7) {
                        BlinkingDot(color: Theme.accent, size: 5)
                        Text(L10n.t(.asstThinking))
                            .font(Theme.subFont)
                            .foregroundStyle(Theme.textTertiary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                    .transition(.opacity)
                }
                if answerShown > 0 {
                    HStack {
                        bubble(answer.prefix(answerShown), color: Theme.textSecondary, fill: Theme.cardFill)
                        Spacer(minLength: 40)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                }
                Spacer(minLength: 0)
                composer
            }
        }
        .storyboard(finalFrame: {
            sent = true
            toolShown = true
            answerShown = answer.count
        }, loop: play)
    }

    private func bubble(_ text: String, color: Color, fill: Color) -> some View {
        Text(text)
            .font(Theme.bodyFont)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }

    private var composer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 1) {
                if askTyped == 0 {
                    Text(L10n.t(.asstPlaceholder))
                        .foregroundStyle(Theme.textQuaternary)
                } else {
                    Text(ask.prefix(askTyped))
                        .foregroundStyle(Theme.textPrimary)
                    StageCaret()
                }
                Spacer(minLength: 0)
                if askTyped > 0 {
                    StageButton(systemName: "arrow.up", size: 24, solid: true, pressed: sendPressed)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .font(Theme.bodyFont)
            .lineLimit(1)
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(height: Theme.inputHeight)
            .background(
                Theme.raisedFill.opacity(0.7),
                in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
            )
            StageButton(systemName: "mic", size: Theme.inputHeight)
        }
        .animation(Theme.stateSpring, value: askTyped == 0)
    }

    private func play() async -> Bool {
        guard await beat(0.7) else { return false }
        for count in 1...ask.count {
            askTyped = count
            guard await beat(0.05) else { return false }
        }
        guard await beat(0.35) else { return false }
        sendPressed = true
        guard await beat(0.12) else { return false }
        sendPressed = false
        withAnimation(Theme.stateSpring) {
            sent = true
            askTyped = 0
        }
        guard await beat(0.3) else { return false }
        withAnimation(.easeOut(duration: 0.2)) { thinking = true }
        guard await beat(0.9) else { return false }
        withAnimation(.easeOut(duration: 0.2)) { toolShown = true }
        guard await beat(0.8) else { return false }
        withAnimation(.easeOut(duration: 0.15)) { thinking = false }
        speaking = true
        let step = answer.count > 30 ? 0.03 : 0.08
        for count in 1...answer.count {
            withAnimation(.easeOut(duration: 0.12)) { answerShown = count }
            guard await beat(step) else { return false }
        }
        guard await beat(2.6) else { return false }
        speaking = false
        withAnimation(.easeIn(duration: 0.3)) {
            sent = false
            toolShown = false
            answerShown = 0
        }
        return await beat(0.5)
    }
}
