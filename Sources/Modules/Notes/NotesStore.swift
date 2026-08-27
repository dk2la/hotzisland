import Foundation
import Observation
import OSLog

/// "Notes" module: a user-chosen folder of Markdown files, Obsidian-style.
/// The store owns the folder scan, the open editor's buffer and a debounced
/// autosave. External edits are picked up by a periodic stat-only rescan —
/// a directory kqueue would miss in-place content edits anyway.
@MainActor
@Observable
final class NotesStore {
    private(set) var notes: [NoteFile] = []
    private(set) var folderURL: URL
    private(set) var openNote: NoteFile?
    var editorText: String = ""
    var editorTitle: String = ""
    private(set) var isDirty = false
    private(set) var lastError: String?

    /// Single shell callback: true while a text field owns the keyboard.

    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "notes")
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var openNoteLoadedMtime: Date?
    @ObservationIgnored private static let folderKey = "settings.notes.folder"

    init() {
        if let stored = UserDefaults.standard.string(forKey: Self.folderKey) {
            folderURL = URL(fileURLWithPath: stored, isDirectory: true)
        } else {
            folderURL = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("HotzIsland Notes", isDirectory: true)
        }
        rescan()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.rescan()
            }
        }
        log.info("folder=\(self.folderURL.path, privacy: .public) notes=\(self.notes.count, privacy: .public)")
    }

    // MARK: - Folder

    func setFolder(_ url: URL) {
        flush()
        closeEditor()
        folderURL = url
        defaults.set(url.path, forKey: Self.folderKey)
        log.info("folder -> \(url.path, privacy: .public)")
        rescan()
    }

    /// Creates the folder lazily — only when the first write needs it.
    private func ensureFolder() throws {
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Scan

    func rescan() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        var scanned: [NoteFile] = []
        for url in files where url.pathExtension.lowercased() == "md" {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            scanned.append(NoteFile(
                url: url,
                title: url.deletingPathExtension().lastPathComponent,
                modifiedAt: mtime
            ))
        }
        scanned.sort { $0.modifiedAt > $1.modifiedAt }
        if scanned != notes {
            notes = scanned
        }
        reloadOpenNoteIfChangedExternally()
    }

    private func reloadOpenNoteIfChangedExternally() {
        guard let open = openNote,
              let diskMtime = (try? open.url.resourceValues(forKeys: [.contentModificationDateKey]))?
                  .contentModificationDate,
              let loaded = openNoteLoadedMtime,
              diskMtime > loaded
        else { return }
        if isDirty {
            // Concurrent edit: keep the user's buffer, last write wins.
            log.info("conflict on \(open.title, privacy: .public) — keeping local edits")
            return
        }
        editorText = Self.read(open.url)
        openNoteLoadedMtime = diskMtime
        log.info("reloaded external edit of \(open.title, privacy: .public)")
    }

    private static func read(_ url: URL) -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        return ""
    }

    // MARK: - Editing

    func open(_ note: NoteFile) {
        flush()
        openNote = note
        editorTitle = note.title
        editorText = Self.read(note.url)
        openNoteLoadedMtime = (try? note.url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        isDirty = false
    }

    func closeEditor() {
        flush()
        openNote = nil
        editorText = ""
        editorTitle = ""
        isDirty = false
        openNoteLoadedMtime = nil
    }

    /// Call on every editor keystroke: marks dirty and re-arms the 1s
    /// autosave.
    func editorChanged() {
        isDirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes the buffer if dirty. Safe to over-call.
    func flush() {
        saveTask?.cancel()
        guard isDirty, let note = openNote else { return }
        do {
            try ensureFolder()
            try editorText.write(to: note.url, atomically: true, encoding: .utf8)
            openNoteLoadedMtime = (try? note.url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            isDirty = false
            lastError = nil
            rescan()
        } catch {
            lastError = error.localizedDescription
            log.error("save failed: \(error, privacy: .public)")
        }
    }

    /// Renames the file when the title field is committed.
    func commitTitle() {
        guard let note = openNote else { return }
        let sanitized = NoteNaming.sanitize(editorTitle)
        guard sanitized != note.title else {
            editorTitle = note.title
            return
        }
        flush()
        let target = NoteNaming.uniqueURL(title: sanitized, in: folderURL)
        do {
            try FileManager.default.moveItem(at: note.url, to: target)
            let renamed = NoteFile(
                url: target,
                title: target.deletingPathExtension().lastPathComponent,
                modifiedAt: note.modifiedAt
            )
            openNote = renamed
            editorTitle = renamed.title
            log.info("renamed \(note.title, privacy: .public) -> \(renamed.title, privacy: .public)")
            rescan()
        } catch {
            lastError = error.localizedDescription
            editorTitle = note.title
            log.error("rename failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Actions

    func create() {
        do {
            try ensureFolder()
            let url = NoteNaming.uniqueURL(title: "Untitled", in: folderURL)
            try "".write(to: url, atomically: true, encoding: .utf8)
            rescan()
            if let note = notes.first(where: { $0.url == url }) {
                open(note)
            }
            log.info("created \(url.lastPathComponent, privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            log.error("create failed: \(error, privacy: .public)")
        }
    }

    func quickCapture(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try ensureFolder()
            let url = NoteNaming.uniqueURL(
                title: NoteNaming.captureName(from: trimmed),
                in: folderURL
            )
            try (trimmed + "\n").write(to: url, atomically: true, encoding: .utf8)
            rescan()
            log.info("captured \(url.lastPathComponent, privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            log.error("capture failed: \(error, privacy: .public)")
        }
    }

    /// Moves the file to the Trash — recoverable, Obsidian-friendly.
    func delete(_ note: NoteFile) {
        if openNote?.id == note.id {
            openNote = nil
            editorText = ""
            editorTitle = ""
            isDirty = false
        }
        do {
            try FileManager.default.trashItem(at: note.url, resultingItemURL: nil)
            rescan()
            log.info("trashed \(note.title, privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            log.error("trash failed: \(error, privacy: .public)")
        }
    }
}
