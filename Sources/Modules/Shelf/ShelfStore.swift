import AppKit
import Observation

/// Temporary parking spot for files dragged onto the notch. Stores
/// references (paths), not copies; entries whose files disappear are
/// dropped on next launch.
@MainActor
@Observable
final class ShelfStore {
    struct Item: Identifiable, Equatable {
        let id: UUID
        let url: URL

        var name: String { url.lastPathComponent }
    }

    private(set) var items: [Item] = []

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private static let key = "shelf.paths"

    init() {
        let paths = defaults.stringArray(forKey: Self.key) ?? []
        items = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { Item(id: UUID(), url: URL(fileURLWithPath: $0)) }
        persist()
    }

    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            guard !items.contains(where: { $0.url == url }) else { continue }
            items.insert(Item(id: UUID(), url: url), at: 0)
        }
        persist()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    private func persist() {
        defaults.set(items.map(\.url.path), forKey: Self.key)
    }
}
