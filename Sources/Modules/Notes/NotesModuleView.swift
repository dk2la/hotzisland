import AppKit
import SwiftUI

/// "Notes" module: list of Markdown files with quick capture at the bottom;
/// opening a note switches to the inline editor.
struct NotesModuleView: View {
    var store: NotesStore
    var speech: SpeechCaptureService

    @State private var captureText = ""
    @FocusState private var captureFocused: Bool

    var body: some View {
        if store.openNote != nil {
            NoteEditorView(store: store, speech: speech)
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.notes.isEmpty {
                DashedZone(
                    label: L10n.t(.notesEmptyTitle),
                    sublabel: L10n.t(.notesEmptySub)
                )
                .frame(maxHeight: 100)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(store.notes) { note in
                            row(note)
                        }
                    }
                }
            }
            SpeechStatusRow(speech: speech)
            captureBar
        }
    }

    private func row(_ note: NoteFile) -> some View {
        Button {
            store.open(note)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    Text(Self.age(of: note))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textQuaternary)
                }
                Spacer(minLength: 0)
                Button {
                    store.delete(note)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.raisedFill))
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private var captureBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField(L10n.t(.notesQuickPlaceholder), text: $captureText)
                    .textFieldStyle(.plain)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textPrimary.opacity(0.92))
                    .focused($captureFocused)
                    .onSubmit(submitCapture)
                if !captureText.isEmpty {
                    // Visible send affordance — Enter works too, but the
                    // button removes any guesswork.
                    CircleGlassButton(systemName: "arrow.up", size: 24, solid: true) {
                        submitCapture()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .frame(minHeight: 36)
            .background(Theme.raisedFill.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .animation(Theme.stateSpring, value: captureText.isEmpty)
            SpeechMicControl(speech: speech) { text in
                captureText = captureText.isEmpty ? text : captureText + " " + text
            }
            GlassCapsuleButton(label: L10n.t(.notesNew)) {
                store.create()
            }
            CircleGlassButton(systemName: "folder", size: 30) {
                pickFolder()
            }
        }
    }

    private func submitCapture() {
        store.quickCapture(captureText)
        captureText = ""
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.folderURL
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            store.setFolder(url)
        }
    }

    private static func age(of note: NoteFile) -> String {
        let minutes = Int(Date().timeIntervalSince(note.modifiedAt) / 60)
        if minutes < 1 { return L10n.t(.ageNow) }
        if minutes < 60 { return L10n.f(.ageMin, minutes) }
        if minutes < 60 * 24 { return L10n.f(.ageHour, minutes / 60) }
        return Self.dateFormatter.string(from: note.modifiedAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

/// Inline Markdown editor: editable title (rename on commit), body with
/// debounced autosave, dictation, Done to flush and return to the list.
struct NoteEditorView: View {
    var store: NotesStore
    var speech: SpeechCaptureService

    @FocusState private var bodyFocused: Bool
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CircleGlassButton(systemName: "chevron.left", size: 28) {
                    store.closeEditor()
                }
                TextField("", text: Bindable(store).editorTitle)
                    .textFieldStyle(.plain)
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.textPrimary.opacity(0.95))
                    .focused($titleFocused)
                    .onSubmit { store.commitTitle() }
                Spacer(minLength: 0)
                SpeechMicControl(speech: speech) { text in
                    appendDictation(text)
                }
                GlassCapsuleButton(label: L10n.t(.notesDone), isPrimary: true) {
                    store.commitTitle()
                    store.closeEditor()
                }
            }
            TextEditor(text: Bindable(store).editorText)
                .scrollContentBackground(.hidden)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textPrimary.opacity(0.92))
                .focused($bodyFocused)
                .padding(8)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .onChange(of: store.editorText) { _, _ in
                    store.editorChanged()
                }
            SpeechStatusRow(speech: speech)
        }
        .onChange(of: titleFocused) { _, focused in
            if !focused {
                store.commitTitle()
            }
        }
        .onDisappear {
            store.flush()
        }
    }

    private func appendDictation(_ text: String) {
        guard !text.isEmpty else { return }
        if store.editorText.isEmpty {
            store.editorText = text
        } else {
            let separator = store.editorText.hasSuffix("\n") ? "" : "\n"
            store.editorText += separator + text
        }
        store.editorChanged()
    }
}

/// Mic button that flips into a recording chip (blinking dot + elapsed +
/// stop). `onFinish` receives the final transcript.
struct SpeechMicControl: View {
    var speech: SpeechCaptureService
    let onFinish: (String) -> Void

    var body: some View {
        if speech.isRecording {
            HStack(spacing: 8) {
                BlinkingDot(color: Theme.critical, size: 6)
                if let startedAt = speech.startedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text(TimeFormat.mmss(context.date.timeIntervalSince(startedAt)))
                            .font(Theme.readoutSFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                CircleGlassButton(systemName: "stop.fill", size: 26, solid: true) {
                    Task {
                        let text = await speech.stop()
                        if !text.isEmpty {
                            onFinish(text)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.cardFill, in: Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else {
            CircleGlassButton(systemName: "mic", size: 30) {
                Task {
                    await speech.start(locale: L10n.shared.language.speechLocale)
                }
            }
        }
    }
}

/// Live transcript line while recording; denied state with a settings link.
struct SpeechStatusRow: View {
    var speech: SpeechCaptureService

    var body: some View {
        if speech.isRecording {
            Text(speech.transcript.isEmpty ? L10n.t(.speechListening) : speech.transcript)
                .font(Theme.subFont)
                .lineLimit(2)
                .truncationMode(.head)
                .foregroundStyle(Theme.accent.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        } else if speech.phase == .denied {
            HStack(spacing: 8) {
                Text(L10n.t(.speechDenied))
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
                GlassCapsuleButton(label: L10n.t(.speechOpenSettings)) {
                    SpeechCaptureService.openPrivacySettings()
                }
            }
            .transition(.opacity)
        }
    }
}
