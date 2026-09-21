import Foundation

/// Names of the user's Shortcuts shortcuts, for the editor's pickers.
/// Read through the `shortcuts` CLI (there is no public API) and cached
/// briefly — the list rarely changes while the editor is open, and the CLI
/// takes a noticeable moment.
enum ShortcutsCatalog {
    private actor Cache {
        private var names: [String] = []
        private var fetchedAt: Date?
        private static let lifetime: TimeInterval = 60

        func names(refresh: @Sendable () async -> [String]) async -> [String] {
            if let fetchedAt, Date().timeIntervalSince(fetchedAt) < Self.lifetime {
                return names
            }
            names = await refresh()
            self.fetchedAt = Date()
            return names
        }
    }

    private static let cache = Cache()

    /// Installed shortcut names, one per line of `shortcuts list`, cached
    /// for 60 s. Empty when the CLI is unavailable.
    static func installedShortcuts() async -> [String] {
        await cache.names(refresh: fetch)
    }

    @Sendable
    private static func fetch() async -> [String] {
        await Process.outputLines("/usr/bin/shortcuts", ["list"])
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

extension Process {
    /// Runs a command-line tool off the main thread and returns its stdout
    /// as non-empty lines; empty when it cannot be launched.
    static func outputLines(_ path: String, _ arguments: [String]) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: [])
                    return
                }
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let lines = String(data: data, encoding: .utf8)?
                    .components(separatedBy: "\n")
                    .filter { !$0.isEmpty } ?? []
                continuation.resume(returning: lines)
            }
        }
    }
}
