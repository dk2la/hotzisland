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
            playbooks = [Playbook(name: "Clear", icon: "moon.zzz.fill", steps: [.closeOtherApps(id: UUID())])]
            save()
            return
        }
        let decoder = JSONDecoder()
        let decodeError: Error
        do {
            playbooks = try decoder.decode([Playbook].self, from: data)
            return
        } catch {
            decodeError = error
        }
        // Pre-steps shape (flat fields): convert once and write the new
        // shape back so the file only ever migrates a single time.
        if let legacy = try? decoder.decode([LegacyPlaybook].self, from: data) {
            playbooks = legacy.map(\.migrated)
            log.info("migrated \(legacy.count, privacy: .public) playbook(s) to the step model")
            save()
            return
        }
        log.error("failed to decode playbooks.json: \(decodeError, privacy: .public)")
        quarantineCorruptFile()
        playbooks = []
    }

    /// Sets the unreadable file aside as "playbooks.corrupt-<timestamp>.json"
    /// so the next save never silently destroys the user's data.
    private func quarantineCorruptFile() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let name = Self.fileURL.deletingPathExtension().lastPathComponent
        let target = Self.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(name).corrupt-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: Self.fileURL, to: target)
            log.error("moved unreadable playbooks.json to \(target.lastPathComponent, privacy: .public)")
        } catch {
            log.error("failed to quarantine playbooks.json: \(error, privacy: .public)")
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

/// The flat, pre-steps playbook: read only to migrate old files.
private struct LegacyPlaybook: Decodable {
    var id: UUID?
    var name: String
    var icon: String?
    var openBundleIDs: [String]?
    var closeOthers: Bool?
    var shortcutName: String?
    var timerMinutes: Int?

    /// Natural order of the old runner: close others → open apps →
    /// shortcut → timer.
    var migrated: Playbook {
        var steps: [PlaybookStep] = []
        if closeOthers == true {
            steps.append(.closeOtherApps(id: UUID()))
        }
        if let openBundleIDs, !openBundleIDs.isEmpty {
            steps.append(.openApps(id: UUID(), bundleIDs: openBundleIDs, layout: .none))
        }
        if let shortcutName, !shortcutName.isEmpty {
            steps.append(.runShortcut(id: UUID(), name: shortcutName))
        }
        if let timerMinutes, timerMinutes > 0 {
            steps.append(.startTimer(id: UUID(), minutes: timerMinutes))
        }
        return Playbook(id: id ?? UUID(), name: name, icon: icon ?? "bolt.fill", steps: steps)
    }
}
