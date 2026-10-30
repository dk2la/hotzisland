import AppKit
import SwiftUI

/// "Notes" module: the last edited note as a hero card with its opening
/// lines, the rest as one grouped list, quick capture at the bottom;
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
        VStack(alignment: .leading, spacing: 10) {
            if let latest = store.notes.first {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        hero(latest)
                        let rest = Array(store.notes.dropFirst())
                        if !rest.isEmpty {
                            GroupedCard {
                                ForEach(Array(rest.enumerated()), id: \.element.id) { index, note in
                                    NoteRow(note: note, age: Self.age(of: note), isLast: index == rest.count - 1) {
                                        store.open(note)
                                    } onDelete: {
                                        store.delete(note)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                EmptyStateZone(
                    label: L10n.t(.notesEmptyTitle),
                    sublabel: L10n.t(.notesEmptySub)
                )
                .frame(maxHeight: 100)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            SpeechStatusRow(speech: speech)
            captureBar
        }
        .animation(Theme.stateSpring, value: speech.isRecording)
        // Opening the module is consent enough to read the folder.
        .onAppear { store.activate() }
    }

    private func hero(_ note: NoteFile) -> some View {
        Button {
            store.open(note)
        } label: {
            HeroCard {
                HStack(spacing: 0) {
                    Text(L10n.t(.notesContinue))
                        .heroCaption()
                    Text(" · \(Self.age(of: note))")
                        .font(Theme.subFont)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(note.title)
                    .font(Theme.heroFont)
                    .lineLimit(2)
                    .foregroundStyle(Theme.textPrimary)
                NotePreview(note: note)
            }
        }
        .buttonStyle(PressableStyle())
    }

    private var captureBar: some View {
        ComposerBar {
            SpeechMicControl(speech: speech, size: 30) { text in
                captureText = captureText.isEmpty ? text : captureText + " " + text
            }
            TextField(L10n.t(.notesQuickPlaceholder), text: $captureText)
                .textFieldStyle(.plain)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textPrimary)
                .focused($captureFocused)
                .onSubmit(submitCapture)
            if captureText.isEmpty {
                ModuleButton(systemName: "folder", height: 30) {
                    store.pickFolder(activating: true)
                }
                .help(L10n.t(.notesFolder))
            } else {
                // Visible send affordance — Enter works too, but the button
                // removes any guesswork.
                ModuleButton(systemName: "arrow.up", kind: .light, height: 30) {
                    submitCapture()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .animation(Theme.stateSpring, value: captureText.isEmpty)
    }

    private func submitCapture() {
        store.quickCapture(captureText)
        captureText = ""
    }

    private static func age(of note: NoteFile) -> String {
        L10n.age(since: note.modifiedAt, olderThanADay: dateFormatter)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

/// One note in the grouped list; the remove button shows on hover only.
private struct NoteRow: View {
    let note: NoteFile
    let age: String
    let isLast: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                Text(note.title)
                    .font(Theme.bodyFont)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if hovered {
                    RowRemoveButton(action: onDelete)
                        .transition(.opacity)
                } else {
                    Text(age)
                        .font(Theme.subFont)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(minHeight: 24)
            .groupedRow(isLast: isLast)
        }
        .buttonStyle(PressableStyle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

/// The opening lines of a note, read off disk once per note and modification.
private struct NotePreview: View {
    let note: NoteFile

    @State private var text = ""

    var body: some View {
        Text(text)
            .font(Theme.bodyFont)
            .lineSpacing(3)
            .lineLimit(3)
            .truncationMode(.tail)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(text.isEmpty ? 0 : 1)
            .task(id: "\(note.id)|\(note.modifiedAt.timeIntervalSince1970)") {
                text = await Self.load(note.url)
            }
    }

    /// Body text without Markdown headings, flattened to one paragraph.
    private static func load(_ url: URL) async -> String {
        await Task.detached(priority: .utility) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
            defer { try? handle.close() }
            let data = (try? handle.read(upToCount: 2048)) ?? Data()
            let raw = String(decoding: data, as: UTF8.self)
            return raw
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                .joined(separator: " ")
        }.value
    }
}

/// Inline Markdown editor: editable title (rename on commit), body with
/// debounced autosave, dictation. The way back to the list is the panel
/// header's chevron — the editor carries no chrome of its own.
struct NoteEditorView: View {
    var store: NotesStore
    var speech: SpeechCaptureService

    @FocusState private var bodyFocused: Bool
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: Bindable(store).editorTitle)
                .textFieldStyle(.plain)
                .font(Theme.titleFont)
                .foregroundStyle(Theme.textPrimary)
                .focused($titleFocused)
                .onSubmit { store.commitTitle() }
            TextEditor(text: Bindable(store).editorText)
                .scrollContentBackground(.hidden)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textPrimary)
                .focused($bodyFocused)
                .padding(8)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .onChange(of: store.editorText) { _, _ in
                    store.editorChanged()
                }
            if let notice = store.lastError {
                // Save failures and conflict diversions surface here.
                Text(notice)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
            SpeechStatusRow(speech: speech)
            HStack {
                SpeechMicControl(speech: speech) { text in
                    appendDictation(text)
                }
                Spacer(minLength: 0)
            }
        }
        .animation(Theme.stateSpring, value: speech.isRecording)
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
    /// Height of the idle button and the recording chip.
    var size: CGFloat = Theme.inputHeight
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
                CircleGlassButton(systemName: "stop.fill", size: size - 10, solid: true) {
                    Task {
                        let text = await speech.stop()
                        if !text.isEmpty {
                            onFinish(text)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: size)
            .background(Theme.cardFill, in: Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else {
            CircleGlassButton(systemName: "mic", size: size) {
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
