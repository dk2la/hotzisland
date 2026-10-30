import SwiftUI

/// Notes: a note types itself, then the mic takes over and a dictated line
/// lands word by word — and the file underneath reports it saved.
struct NotesStage: View {
    @State private var typed = 0
    @State private var dictated = 0
    @State private var listening = false
    @State private var recordSeconds = 0
    @State private var saved = false

    private var noteBody: TypedText { TypedText(L10n.t(.obMockNoteBody), byWord: false) }
    private var dictation: TypedText { TypedText(L10n.t(.obMockNoteDictation)) }

    private var text: String {
        let typedPart = noteBody.prefix(typed)
        guard dictated > 0 else { return typedPart }
        return typedPart + "\n" + dictation.prefix(dictated)
    }

    var body: some View {
        StagePanel(title: ModuleTab.notes.title, showsBack: true) {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.t(.obMockNoteTitle))
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 10)
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text(text)
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                    StageCaret(height: 14)
                        .alignmentGuide(.lastTextBaseline) { $0[.bottom] - 3 }
                }
                Spacer(minLength: 0)
                micBar
                fileLine
                    .padding(.top, 10)
            }
        }
        .storyboard(finalFrame: {
            typed = noteBody.count
            dictated = dictation.count
            saved = true
        }, loop: play)
    }

    /// Dictation, drawn like the notes module's own control: a red pulse,
    /// the elapsed time, live levels, and the stop key.
    @ViewBuilder
    private var micBar: some View {
        if listening {
            HStack(spacing: 8) {
                BlinkingDot(color: Theme.critical, size: 6)
                Text(String(format: "00:%02d", recordSeconds))
                    .font(Theme.readoutSFont)
                    .foregroundStyle(Theme.textSecondary)
                Waveform()
                    .frame(height: 16)
                StageButton(systemName: "stop.fill", size: 26, solid: true)
            }
            .padding(.horizontal, 10)
            .frame(height: Theme.inputHeight)
            .background(Theme.cardFill, in: Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else {
            HStack {
                Spacer(minLength: 0)
                StageButton(systemName: "mic", size: Theme.inputHeight)
            }
            .transition(.opacity)
        }
    }

    /// Where the note lives — plain Markdown on disk.
    private var fileLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textQuaternary)
            Text("~/Notes/\(L10n.t(.obMockNoteTitle)).md")
                .font(Theme.readoutSFont)
                .foregroundStyle(Theme.textQuaternary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                Text(L10n.t(.obSaved).uppercased())
                    .font(Theme.labelFont)
                    .kerning(1)
            }
            .foregroundStyle(Theme.accent)
            .opacity(saved ? 1 : 0)
            .animation(.easeOut(duration: saved ? 0.1 : 0.6), value: saved)
        }
    }

    private func flashSaved() async -> Bool {
        saved = true
        guard await beat(1.0) else { return false }
        saved = false
        return true
    }

    private func play() async -> Bool {
        guard await beat(0.6) else { return false }
        for count in 1...noteBody.count {
            typed = count
            guard await beat(0.032) else { return false }
        }
        guard await beat(0.3), await flashSaved() else { return false }
        recordSeconds = 0
        withAnimation(Theme.stateSpring) { listening = true }
        guard await beat(0.5) else { return false }
        for count in 1...dictation.count {
            withAnimation(.easeOut(duration: 0.15)) { dictated = count }
            if count % 3 == 0 { recordSeconds += 1 }
            guard await beat(dictation.count > 12 ? 0.08 : 0.24) else { return false }
        }
        guard await beat(0.5) else { return false }
        withAnimation(Theme.stateSpring) { listening = false }
        guard await beat(0.3), await flashSaved() else { return false }
        guard await beat(2.0) else { return false }
        withAnimation(.easeIn(duration: 0.3)) {
            typed = 0
            dictated = 0
        }
        return await beat(0.5)
    }
}

/// Live input levels: a row of bars breathing out of phase.
private struct Waveform: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<18, id: \.self) { index in
                    let phase = t * 7 + Double(index) * 0.8
                    let level = 0.25 + 0.75 * abs(sin(phase) * cos(phase * 0.37 + Double(index)))
                    Capsule()
                        .fill(Theme.textPrimary.opacity(0.75))
                        .frame(width: 2, height: max(2, 16 * level))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
