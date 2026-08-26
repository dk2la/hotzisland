import Foundation
import Network

/// Buffered TLS connection for mail protocols. Implicit TLS only (IMAP 993,
/// SMTP 465) — STARTTLS lands with the send phase. No plaintext mode exists.
actor TLSTransport {
    private let host: String
    private let port: UInt16
    private var connection: NWConnection?
    private var buffer = Data()
    private var isClosed = false

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    func connect(timeout: Duration = .seconds(15)) async throws {
        let options = NWProtocolTLS.Options()
        let parameters = NWParameters(tls: options)
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: parameters
        )
        self.connection = connection

        try await withTimeout(timeout) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let resumed = ResumeGuard()
                connection.stateUpdateHandler = { @Sendable state in
                    switch state {
                    case .ready:
                        if resumed.claim() { continuation.resume() }
                    case .failed(let error):
                        if resumed.claim() { continuation.resume(throwing: MailError.tls(error.localizedDescription)) }
                    case .cancelled:
                        if resumed.claim() { continuation.resume(throwing: MailError.connectionClosed) }
                    default:
                        break
                    }
                }
                connection.start(queue: .global(qos: .userInitiated))
            }
        }
    }

    func close() {
        isClosed = true
        connection?.cancel()
        connection = nil
        buffer.removeAll()
    }

    func send(_ data: Data) async throws {
        guard let connection else { throw MailError.connectionClosed }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { @Sendable error in
                if let error {
                    continuation.resume(throwing: MailError.tls(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// One CRLF-terminated line, terminator included.
    func readLine(timeout: Duration = .seconds(15)) async throws -> Data {
        try await withTimeout(timeout) { try await self.readLineLoop() }
    }

    func read(exactly count: Int, timeout: Duration = .seconds(30)) async throws -> Data {
        try await withTimeout(timeout) { try await self.readExactLoop(count) }
    }

    private func readLineLoop() async throws -> Data {
        while true {
            if let range = buffer.range(of: Data([13, 10])) {
                let result = Data(buffer[..<range.upperBound])
                buffer.removeSubrange(..<range.upperBound)
                return result
            }
            try await receiveMore()
        }
    }

    private func readExactLoop(_ count: Int) async throws -> Data {
        while buffer.count < count {
            try await receiveMore()
        }
        let result = Data(buffer.prefix(count))
        buffer.removeFirst(count)
        return result
    }

    private func receiveMore() async throws {
        guard let connection, !isClosed else { throw MailError.connectionClosed }
        let chunk: Data = try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { @Sendable data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: MailError.tls(error.localizedDescription))
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: MailError.connectionClosed)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
        buffer.append(chunk)
    }

    private func withTimeout<T: Sendable>(
        _ timeout: Duration,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw MailError.timeout
            }
            guard let result = try await group.next() else { throw MailError.timeout }
            group.cancelAll()
            return result
        }
    }
}

/// Stream-backed transport for SMTP. Unlike NWConnection, CFStream can raise
/// TLS on a socket that is already open, which is exactly what STARTTLS (587)
/// needs; implicit TLS (465) just switches it on before opening. The streams
/// run unscheduled and are polled, so no run loop is involved.
actor StreamTransport {
    private let host: String
    private let port: UInt16
    private var input: InputStream?
    private var output: OutputStream?
    private var buffer = Data()

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    func connect(useTLS: Bool, timeout: Duration = .seconds(15)) async throws {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, host as CFString, UInt32(port), &readStream, &writeStream)
        guard let read = readStream?.takeRetainedValue(), let write = writeStream?.takeRetainedValue() else {
            throw MailError.connectionClosed
        }
        let input = read as InputStream
        let output = write as OutputStream
        self.input = input
        self.output = output
        if useTLS { enableTLS() }
        input.open()
        output.open()

        let deadline = ContinuousClock.now + timeout
        while input.streamStatus == .opening || output.streamStatus == .opening {
            try await tick(deadline: deadline)
        }
        guard input.streamStatus != .error, output.streamStatus != .error else {
            throw MailError.tls(streamErrorText())
        }
    }

    /// Upgrades an open plaintext socket. Any bytes already buffered are
    /// dropped — the server must not have sent any past its STARTTLS reply.
    func startTLS() throws {
        guard input != nil, output != nil else { throw MailError.connectionClosed }
        buffer.removeAll()
        enableTLS()
        guard input?.streamStatus != .error, output?.streamStatus != .error else {
            throw MailError.tls(streamErrorText())
        }
    }

    func close() {
        input?.close()
        output?.close()
        input = nil
        output = nil
        buffer.removeAll()
    }

    func send(_ data: Data, timeout: Duration = .seconds(15)) async throws {
        guard let output else { throw MailError.connectionClosed }
        let deadline = ContinuousClock.now + timeout
        var remaining = data
        while !remaining.isEmpty {
            while !output.hasSpaceAvailable {
                if output.streamStatus == .error { throw MailError.tls(streamErrorText()) }
                try await tick(deadline: deadline)
            }
            let written = remaining.withUnsafeBytes { raw -> Int in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return output.write(base, maxLength: raw.count)
            }
            guard written > 0 else { throw MailError.tls(streamErrorText()) }
            remaining.removeFirst(written)
        }
    }

    /// One CRLF-terminated line, terminator included.
    func readLine(timeout: Duration = .seconds(30)) async throws -> Data {
        let deadline = ContinuousClock.now + timeout
        while true {
            if let range = buffer.range(of: Data([13, 10])) {
                let line = Data(buffer[..<range.upperBound])
                buffer.removeSubrange(..<range.upperBound)
                return line
            }
            try await receiveMore(deadline: deadline)
        }
    }

    private func enableTLS() {
        let level = StreamSocketSecurityLevel.negotiatedSSL.rawValue
        input?.setProperty(level, forKey: .socketSecurityLevelKey)
        output?.setProperty(level, forKey: .socketSecurityLevelKey)
    }

    private func receiveMore(deadline: ContinuousClock.Instant) async throws {
        guard let input else { throw MailError.connectionClosed }
        while !input.hasBytesAvailable {
            switch input.streamStatus {
            case .atEnd, .closed: throw MailError.connectionClosed
            case .error: throw MailError.tls(streamErrorText())
            default: try await tick(deadline: deadline)
            }
        }
        var chunk = [UInt8](repeating: 0, count: 8192)
        let count = input.read(&chunk, maxLength: chunk.count)
        if count < 0 { throw MailError.tls(streamErrorText()) }
        if count == 0 { throw MailError.connectionClosed }
        buffer.append(contentsOf: chunk[..<count])
    }

    private func tick(deadline: ContinuousClock.Instant) async throws {
        guard ContinuousClock.now < deadline else { throw MailError.timeout }
        try await Task.sleep(for: .milliseconds(10))
    }

    private func streamErrorText() -> String {
        (input?.streamError ?? output?.streamError)?.localizedDescription ?? "stream failed"
    }
}

/// One-shot continuation guard for NWConnection's repeated state callbacks.
final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
