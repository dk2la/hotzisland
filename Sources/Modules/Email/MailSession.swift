import Foundation
import OSLog

extension Duration {
    /// Whole milliseconds, for log lines.
    var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}

/// Keeps one authenticated IMAP connection alive and hands it to callers in
/// turn. Opening a session costs a TLS handshake, a LOGIN and a SELECT — on a
/// large mailbox that is seconds, which is why the widget used to freeze on
/// "…" every time a message was opened.
///
/// Actor isolation alone does not serialize callers: an actor is reentrant
/// at every `await`, so two `run` calls would send tagged commands on the
/// same socket and steal each other's replies. Calls are therefore chained —
/// each waits for the previous one to finish before touching the client.
/// A dropped or timed-out connection is transparent: the call is retried
/// once on a freshly opened session.
actor MailSession {
    /// Builds the transport for a fresh connection to (host, port).
    typealias TransportFactory = @Sendable (String, UInt16) -> any MailLineTransport

    private let host: String
    private let port: UInt16
    private let user: String
    private let password: String
    private let makeTransport: TransportFactory
    private var client: IMAPClient?
    private var openedAt = Date.distantPast
    private var lastUsedAt = Date.distantPast
    private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "email")

    /// Servers drop idle IMAP connections (Gmail after ~30 min). Well before
    /// that we reconnect rather than discover it mid-command.
    private static let maxAge: TimeInterval = 10 * 60
    /// A connection used seconds ago is alive — pinging it would add a full
    /// round trip to every user action. Probe only after real idle time.
    private static let pingAfterIdle: TimeInterval = 30

    init(
        host: String,
        port: UInt16,
        user: String,
        password: String,
        makeTransport: @escaping TransportFactory = { TLSTransport(host: $0, port: $1) }
    ) {
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.makeTransport = makeTransport
    }

    /// Tail of the command chain; the next `run` waits for it to settle.
    private var tail: Task<Void, Never>?

    /// Runs `body` against a live, INBOX-selected client, strictly after
    /// every earlier `run` on this session has finished.
    func run<T: Sendable>(_ body: @escaping @Sendable (IMAPClient) async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> {
            await previous?.value
            return try await perform(body)
        }
        // The chain only cares about ordering, not about the outcome.
        tail = Task { _ = try? await task.value }
        return try await task.value
    }

    private func perform<T: Sendable>(_ body: @Sendable (IMAPClient) async throws -> T) async throws -> T {
        do {
            let result = try await body(open())
            lastUsedAt = Date()
            return result
        } catch let error as MailError where error.isTransportFailure {
            // The connection may simply have gone stale; one clean retry
            // tells a dead socket apart from a real protocol error. Only
            // transport failures qualify: a NO/BAD or a rejected LOGIN would
            // come back identical (and a repeated MOVE could act twice).
            log.info("session retry after: \(error.localizedDescription, privacy: .public)")
            await close()
            let result = try await body(open())
            lastUsedAt = Date()
            return result
        }
    }

    func close() async {
        if let client {
            await client.logout()
        }
        client = nil
    }

    private func open() async throws -> IMAPClient {
        if let client, Date().timeIntervalSince(openedAt) < Self.maxAge {
            // Recently active connections skip the probe entirely; only one
            // that has sat idle gets a short-timeout NOOP. A dead socket
            // would otherwise burn a full read timeout on the real command.
            if Date().timeIntervalSince(lastUsedAt) < Self.pingAfterIdle {
                return client
            }
            do {
                try await client.ping()
                lastUsedAt = Date()
                return client
            } catch {
                log.info("session ping failed, reconnecting")
            }
        }
        await close()
        let fresh = IMAPClient(transport: makeTransport(host, port))
        try await fresh.connect()
        try await fresh.login(user: user, password: password)
        _ = try await fresh.selectInbox()
        client = fresh
        openedAt = Date()
        log.info("imap session opened")
        return fresh
    }

    /// Fresh EXISTS count for the selected mailbox.
    func reselectInbox() async throws -> Int {
        try await run { try await $0.selectInbox() }
    }
}
