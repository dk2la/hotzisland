import Foundation
import Observation
import OSLog

/// Persists playbooks as JSON in Application Support — user-editable data,
/// not preferences.
@MainActor
@Observable
final class PlaybookStore {
    private(set) var playbooks: [Playbook] = []

    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "playbooks")

    @ObservationIgnored private static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("HotzIsland", isDirectory: true)
            .appendingPathComponent("playbooks.json")
    }()

    init() {
        load()
    }

    func add(_ playbook: Playbook) {
        playbooks.append(playbook)
        save()
    }

    func update(_ playbook: Playbook) {
        guard let index = playbooks.firstIndex(where: { $0.id == playbook.id }) else { return }
        playbooks[index] = playbook
        save()
    }

    func remove(_ playbook: Playbook) {
        playbooks.removeAll { $0.id == playbook.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else {
            // First launch: seed the one universally safe playbook.
            playbooks = [Playbook(name: "Clear", icon: "moon.zzz.fill", closeOthers: true)]
            save()
            return
        }
        do {
            playbooks = try JSONDecoder().decode([Playbook].self, from: data)
        } catch {
            log.error("failed to decode playbooks.json: \(error, privacy: .public)")
            playbooks = []
        }
    }

    private func save() {
        do {
            let directory = Self.fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(playbooks).write(to: Self.fileURL, options: .atomic)
        } catch {
            log.error("failed to save playbooks.json: \(error, privacy: .public)")
        }
    }
}
