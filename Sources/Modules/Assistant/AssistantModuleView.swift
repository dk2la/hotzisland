import SwiftUI

/// "Assistant" module: chat transcript over the widget's modules. User turns
/// sit right on raised glass, assistant turns left, tool calls render as a
/// mono "⚙ set_timer(25)" line.
struct AssistantModuleView: View {
    var assistant: AssistantService
    var speech: SpeechCaptureService
    var voice: SpeechSynthesisService

    @FocusState private var composerFocused: Bool

    var body: some View {
        if assistant.config == nil {
            setupPrompt
        } else {
            chat
        }
    }

    private var setupPrompt: some View {
        ModuleSetupPrompt(title: L10n.t(.asstSetupTitle), sublabel: L10n.t(.asstSetupSub))
    }

    private var chat: some View {
        VStack(spacing: 8) {
            if assistant.transcript.isEmpty {
                // Same register as the Notes empty state: short caps label,
                // the hint as the quiet subline.
                EmptyStateZone(
                    label: L10n.t(.asstEmptyTitle),
                    sublabel: assistant.isVoiceMode ? L10n.t(.asstVoiceHint) : L10n.t(.asstHint)
                )
                .frame(maxHeight: 90)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                transcript
            }
            // Same live dictation line the Notes module shows: the words
            // appear as they are recognised, before the turn is sent.
            SpeechStatusRow(speech: speech)
            composer
        }
        .animation(Theme.stateSpring, value: speech.isRecording)
        // Answers are spoken from here, not from the service, so the audio
        // follows the view that is actually on screen.
        .onChange(of: assistant.pendingSpeech) { _, pending in
            guard pending != nil, let text = assistant.consumePendingSpeech() else { return }
            voice.speak(text, locale: L10n.shared.language.speechLocale)
        }
        .onDisappear { voice.stop() }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(assistant.transcript) { message in
                        row(message)
                    }
                    if assistant.isThinking {
                        HStack(spacing: 6) {
                            BlinkingDot(color: Theme.accent, size: 5)
                            Text(L10n.t(.asstThinking))
                                .font(Theme.subFont)
                                .foregroundStyle(Theme.textTertiary)
                            Spacer(minLength: 0)
                        }
                        .id("thinking")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
            }
            .onChange(of: assistant.transcript.count) {
                withAnimation(Theme.stateSpring) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func row(_ message: AssistantMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        Theme.raisedFill.opacity(0.8),
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    )
            }
        case .assistant:
            HStack {
                Text(message.text)
                    .font(Theme.bodyFont)
                    .foregroundStyle(message.isError ? Theme.critical : Theme.textSecondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        Theme.cardFill,
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    )
                Spacer(minLength: 40)
            }
        case .tool:
            HStack(spacing: 6) {
                Text("⚙ \(message.toolLabel ?? "")")
                    .font(Theme.readoutSFont)
                    .foregroundStyle(message.isError ? Theme.critical : Theme.textQuaternary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField(L10n.t(.asstPlaceholder), text: Bindable(assistant).draft)
                    .textFieldStyle(.plain)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textPrimary)
                    .focused($composerFocused)
                    .onSubmit { assistant.send() }
                if !assistant.draft.isEmpty, !assistant.isThinking {
                    CircleGlassButton(systemName: "arrow.up", size: 24, solid: true) {
                        assistant.send()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .frame(minHeight: 36)
            .background(Theme.raisedFill.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .animation(Theme.stateSpring, value: assistant.draft.isEmpty)
            SpeechMicControl(speech: speech) { text in
                voice.stop() // barge-in: speaking over the answer replaces it
                assistant.acceptDictation(text)
            }
            // Voice-mode toggle and transcript clearing live in the panel
            // header; only the in-the-moment mute belongs down here.
            if voice.isSpeaking {
                CircleGlassButton(systemName: "speaker.slash", size: 30) {
                    voice.stop()
                }
                .transition(.opacity)
            }
        }
        .animation(Theme.stateSpring, value: voice.isSpeaking)
    }
}
