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
/// An actor, so commands can never interleave on the shared socket. A dropped
/// or timed-out connection is transparent: the call is retried once on a
/// freshly opened session.
actor MailSession {
    private let host: String
    private let port: UInt16
    private let user: String
    private let password: String
    private var client: IMAPClient?
    private var openedAt = Date.distantPast
    private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "email")

    /// Servers drop idle IMAP connections (Gmail after ~30 min). Well before
    /// that we reconnect rather than discover it mid-command.
    private static let maxAge: TimeInterval = 10 * 60

    init(host: String, port: UInt16, user: String, password: String) {
        self.host = host
        self.port = port
        self.user = user
        self.password = password
    }

    /// Runs `body` against a live, INBOX-selected client.
    func run<T: Sendable>(_ body: @Sendable (IMAPClient) async throws -> T) async throws -> T {
        do {
            return try await body(open())
        } catch {
            // The connection may simply have gone stale; one clean retry
            // tells a dead socket apart from a real protocol error.
            log.info("session retry after: \(error.localizedDescription, privacy: .public)")
            await close()
            return try await body(open())
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
            // Confirm the socket is still alive before handing it out: a
            // dead one would otherwise burn a full read timeout.
            do {
                try await client.ping()
                return client
            } catch {
                log.info("session ping failed, reconnecting")
            }
        }
        await close()
        let fresh = IMAPClient(host: host, port: port)
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
