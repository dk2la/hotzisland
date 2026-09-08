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
    /// Buffer as last read from / written to disk. `editorChanged()` compares
    /// against it so programmatic loads never count as user edits.
    @ObservationIgnored private var savedText = ""
    @ObservationIgnored private var scanInFlight = false
    @ObservationIgnored private var rescanRequested = false
    @ObservationIgnored private static let folderKey = "settings.notes.folder"
    /// Folders never worth walking: Obsidian internals, its trash, JS deps.
    @ObservationIgnored nonisolated private static let skippedDirectories: Set<String> = [".obsidian", ".trash", "node_modules"]
    @ObservationIgnored private static let conflictStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter
    }()

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
        log.info("folder=\(self.folderURL.path, privacy: .public)")
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

    /// Kicks off a recursive walk off the main actor; the result lands in
    /// `applyScan`. Overlapping requests collapse into one follow-up walk.
    func rescan() {
        guard !scanInFlight else {
            rescanRequested = true
            return
        }
        scanInFlight = true
        rescanRequested = false
        let folder = folderURL
        Task.detached(priority: .utility) { [weak self] in
            let scanned = Self.scanFolder(folder)
            await self?.applyScan(scanned, for: folder)
        }
    }

    private func applyScan(_ scanned: [NoteFile], for folder: URL) {
        scanInFlight = false
        defer {
            if rescanRequested {
                rescan()
            }
        }
        // A folder switch raced the walk: its result is for the old root.
        guard folder == folderURL else { return }
        if scanned != notes {
            notes = scanned
            log.debug("scan notes=\(scanned.count, privacy: .public)")
        }
        reloadOpenNoteIfChangedExternally()
    }

    /// Recursive .md walk, sorted by mtime desc. Runs off the main actor.
    nonisolated private static func scanFolder(_ folder: URL) -> [NoteFile] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var scanned: [NoteFile] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isDirectory == true {
                if skippedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard url.pathExtension.lowercased() == "md" else { continue }
            scanned.append(NoteFile(
                url: url,
                title: url.deletingPathExtension().lastPathComponent,
                modifiedAt: values?.contentModificationDate ?? .distantPast
            ))
        }
        scanned.sort { $0.modifiedAt > $1.modifiedAt }
        return scanned
    }

    private func reloadOpenNoteIfChangedExternally() {
        guard let open = openNote,
              let diskMtime = Self.mtime(open.url),
              let loaded = openNoteLoadedMtime,
              diskMtime > loaded
        else { return }
        if isDirty {
            divertLocalEdits(of: open, diskMtime: diskMtime)
            return
        }
        savedText = Self.read(open.url)
        editorText = savedText
        openNoteLoadedMtime = diskMtime
        log.info("reloaded external edit of \(open.title, privacy: .public)")
    }

    /// Concurrent edit: the disk version wins, the local buffer goes to a
    /// sibling "<title> (conflict <stamp>).md" so nothing is lost either way.
    private func divertLocalEdits(of note: NoteFile, diskMtime: Date) {
        let stamp = Self.conflictStamp.string(from: Date())
        let target = NoteNaming.uniqueURL(
            title: "\(note.title) (conflict \(stamp))",
            in: note.url.deletingLastPathComponent()
        )
        do {
            try editorText.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            // Keep the buffer dirty: the next flush retries the diversion.
            lastError = error.localizedDescription
            log.error("conflict copy failed: \(error, privacy: .public)")
            return
        }
        let conflictTitle = target.deletingPathExtension().lastPathComponent
        saveTask?.cancel()
        savedText = Self.read(note.url)
        editorText = savedText
        openNoteLoadedMtime = diskMtime
        isDirty = false
        lastError = "Edited elsewhere — your version was saved as “\(conflictTitle)”"
        log.info("conflict on \(note.title, privacy: .public) -> \(conflictTitle, privacy: .public)")
        rescan()
    }

    nonisolated private static func mtime(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
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
        savedText = Self.read(note.url)
        editorText = savedText
        openNoteLoadedMtime = Self.mtime(note.url)
        isDirty = false
        lastError = nil
    }

    func closeEditor() {
        flush()
        openNote = nil
        savedText = ""
        editorText = ""
        editorTitle = ""
        isDirty = false
        openNoteLoadedMtime = nil
    }

    /// Call on every editor keystroke: marks dirty and re-arms the 1s
    /// autosave. A buffer equal to the saved text (programmatic load, undo
    /// back to the saved state) is not an edit.
    func editorChanged() {
        guard editorText != savedText else {
            saveTask?.cancel()
            isDirty = false
            return
        }
        isDirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes the buffer if dirty. Safe to over-call. Never overwrites a
    /// version that changed on disk since it was read.
    func flush() {
        saveTask?.cancel()
        guard isDirty, let note = openNote else { return }
        if let diskMtime = Self.mtime(note.url),
           let loaded = openNoteLoadedMtime,
           diskMtime > loaded {
            divertLocalEdits(of: note, diskMtime: diskMtime)
            return
        }
        do {
            try ensureFolder()
            try editorText.write(to: note.url, atomically: true, encoding: .utf8)
            savedText = editorText
            openNoteLoadedMtime = Self.mtime(note.url)
            isDirty = false
            lastError = nil
            rescan()
        } catch {
            lastError = error.localizedDescription
            log.error("save failed: \(error, privacy: .public)")
        }
    }

    /// Renames the file when the title field is committed. The note stays
    /// in its own (possibly nested) folder.
    func commitTitle() {
        guard let note = openNote else { return }
        let sanitized = NoteNaming.sanitize(editorTitle)
        guard sanitized != note.title else {
            editorTitle = note.title
            return
        }
        flush()
        let target = NoteNaming.uniqueURL(title: sanitized, in: note.url.deletingLastPathComponent())
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
            // The scan is async; open the new note right away.
            let note = NoteFile(
                url: url,
                title: url.deletingPathExtension().lastPathComponent,
                modifiedAt: Self.mtime(url) ?? Date()
            )
            notes.insert(note, at: 0)
            open(note)
            rescan()
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
            saveTask?.cancel()
            openNote = nil
            savedText = ""
            editorText = ""
            editorTitle = ""
            isDirty = false
            openNoteLoadedMtime = nil
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
