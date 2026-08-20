import Foundation

/// Runs AppleScript via `osascript` off the main thread. Errors surface as
/// `nil` (stderr is swallowed — sources treat any failure as "no data").
enum AppleScriptRunner {
    static func run(_ script: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()
            process.terminationHandler = { _ in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: (output?.isEmpty ?? true) ? nil : output)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
