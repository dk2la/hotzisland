import AppKit
import Observation

/// Text clipboard history. Kept in memory only — persisting clipboard
/// contents to disk would be a privacy hazard.
@MainActor
@Observable
final class ClipboardStore {
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let text: String
        let copiedAt: Date
    }

    private(set) var entries: [Entry] = []

    @ObservationIgnored private var lastChangeCount = NSPasteboard.general.changeCount
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    private static let capacity = 25
    /// Password managers mark secrets with this type — never record them.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    init() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Demo mode

    /// Scripted history; the pasteboard is not watched while it is shown,
    /// so a stray copy during recording never lands in the list.
    private(set) var isDemo = false
    @ObservationIgnored private var parkedEntries: [Entry] = []

    func enterDemo(entries demoEntries: [Entry]) {
        guard !isDemo else { return }
        isDemo = true
        parkedEntries = entries
        entries = demoEntries
    }

    func exitDemo() {
        guard isDemo else { return }
        isDemo = false
        entries = parkedEntries
        parkedEntries = []
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func poll() {
        guard !isDemo else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let types = pasteboard.types ?? []
        guard !types.contains(Self.concealedType), !types.contains(Self.transientType),
              let text = pasteboard.string(forType: .string)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              text != entries.first?.text
        else { return }

        entries.removeAll { $0.text == text }
        entries.insert(Entry(id: UUID(), text: String(text.prefix(10_000)), copiedAt: Date()), at: 0)
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
    }

    /// Puts an entry back onto the pasteboard and moves it to the top.
    func copy(_ entry: Entry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        // Our own write must not be re-captured as a new entry.
        lastChangeCount = pasteboard.changeCount
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
    }

    func clear() {
        entries.removeAll()
    }
}
