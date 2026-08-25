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
