import Foundation

/// Runs AppleScript via `osascript` off the main thread. Errors surface as
/// `nil` (stderr is swallowed — sources treat any failure as "no data").
///
/// Both pipes are drained while the child runs — reading only after exit
/// would deadlock on anything above the 64 KB pipe buffer — and a hard
/// timeout kills a stuck `osascript` so callers never hang.
enum AppleScriptRunner {
    private static let timeout: TimeInterval = 10

    static func run(_ script: String) async -> String? {
        await withCheckedContinuation { continuation in
            let job = Job(continuation)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { _ in job.processExited() }
            do {
                try process.run()
            } catch {
                job.launchFailed()
                return
            }
            job.adopt(process)

            let queue = DispatchQueue.global(qos: .utility)
            let out = stdout.fileHandleForReading
            let err = stderr.fileHandleForReading
            queue.async { job.stdoutDrained(out.readDataToEndOfFile()) }
            queue.async {
                _ = err.readDataToEndOfFile()
                job.stderrDrained()
            }
            queue.asyncAfter(deadline: .now() + timeout) { job.timedOut() }
        }
    }

    /// State shared by the drain closures, the termination handler and the
    /// timeout — all of which run on arbitrary threads. Resumes exactly once.
    private final class Job: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<String?, Never>?
        private var process: Process?
        private var output = Data()
        private var exited = false
        private var stdoutDone = false
        private var stderrDone = false

        init(_ continuation: CheckedContinuation<String?, Never>) {
            self.continuation = continuation
        }

        func adopt(_ process: Process) {
            lock.lock()
            defer { lock.unlock() }
            // The child may already be gone if it exited before we got here.
            if !exited { self.process = process }
        }

        func launchFailed() {
            resume(returning: nil)
        }

        func processExited() {
            lock.lock()
            exited = true
            process = nil
            lock.unlock()
            finishIfComplete()
        }

        func stdoutDrained(_ data: Data) {
            lock.lock()
            output = data
            stdoutDone = true
            lock.unlock()
            finishIfComplete()
        }

        func stderrDrained() {
            lock.lock()
            stderrDone = true
            lock.unlock()
            finishIfComplete()
        }

        /// Kill the child and give up. The drains still reach EOF once the
        /// process dies, but nobody is waiting for them anymore.
        func timedOut() {
            lock.lock()
            let process = self.process
            self.process = nil
            lock.unlock()
            process?.terminate()
            resume(returning: nil)
        }

        /// Resumes once the process has exited and both pipes hit EOF.
        private func finishIfComplete() {
            lock.lock()
            guard exited, stdoutDone, stderrDone else {
                lock.unlock()
                return
            }
            let text = String(data: output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lock.unlock()
            resume(returning: (text?.isEmpty ?? true) ? nil : text)
        }

        private func resume(returning value: String?) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: value)
        }
    }
}
