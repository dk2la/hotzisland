import Foundation
import OSLog

extension Duration {
    /// Whole milliseconds, for log lines.
    var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}

/// Errors of the session itself, as opposed to the wire (`MailError`).
enum MailSessionError: Error, LocalizedError {
    /// The server does not advertise IDLE; the caller has to poll.
    case idleUnsupported

    var errorDescription: String? {
        switch self {
        case .idleUnsupported: "Server does not support IDLE"
        }
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
///
/// IDLE (RFC 2177) sits beside the chain, not in it: an open-ended wait
/// inside the chain would starve every `run`. Entering IDLE *is* a chained
/// step — it cannot start while a reply is still streaming — but the wait
/// for updates continues in a side task. `run` first ends that wait (DONE,
/// tagged OK), then executes its body; `idle` returns to its caller as
/// interrupted and the caller re-enters, which queues the fresh IDLE
/// behind whatever commands are pending. See `idle(onEvent:)`.
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

    /// Runs `body` against a live client, strictly after every earlier
    /// `run` on this session has finished. A fresh connection opens with
    /// INBOX selected; a body that needs a particular mailbox should go
    /// through `run(in:)`, since an earlier call may have moved elsewhere.
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

    /// `run`, with `mailbox` selected first. SELECT only goes out when the
    /// connection has a different mailbox open — the reply lists flags and
    /// counts, a round trip not worth repeating on every command. The
    /// select sits inside the chained body, so a retry on a fresh socket
    /// (which opens on INBOX) re-selects too.
    func run<T: Sendable>(
        in mailbox: String,
        _ body: @escaping @Sendable (IMAPClient) async throws -> T
    ) async throws -> T {
        try await run { client in
            if await client.selectedMailbox != mailbox {
                _ = try await client.select(mailbox)
            }
            return try await body(client)
        }
    }

    private func perform<T: Sendable>(_ body: @Sendable (IMAPClient) async throws -> T) async throws -> T {
        // A command must own the socket: end the idle wait before touching it.
        await interruptIdle()
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
        await interruptIdle()
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

    // MARK: - IDLE

    /// The side task reading idle updates; nil when not idling.
    private var idleTask: Task<Void, Error>?
    /// Re-issues IDLE before the server drops it.
    private var idleTimer: Task<Void, Never>?
    /// Whether the current idle is being ended for a command or `close`
    /// (return to the caller) rather than by the timer (re-issue).
    private var idleInterrupted = false
    /// Servers end an IDLE at ~29 minutes; well before that we DONE and
    /// re-issue it ourselves.
    private static let idleReissueAfter: Duration = .seconds(25 * 60)
    /// How long DONE may go unanswered before the socket is dropped.
    private static let idleStopGrace: Duration = .seconds(10)

    private enum IdleOutcome {
        case interrupted
        case expired
        case failed(Error)
    }

    /// Waits for mailbox changes on the session's connection, calling
    /// `onEvent` for each. Returns when a `run` (or `close`, or cancelling
    /// the calling task) needed the connection — re-enter to keep idling;
    /// the fresh IDLE queues behind the commands that interrupted it.
    /// Throws `MailSessionError.idleUnsupported` when the server lacks IDLE
    /// and a `MailError` when the transport fails; the caller reconnects by
    /// running any command (that path retries on a fresh socket).
    func idle(onEvent: @escaping @Sendable (IMAPClient.IdleEvent) -> Void) async throws {
        try await withTaskCancellationHandler {
            while true {
                try Task.checkCancellation()
                try await run { client in
                    try await self.enterIdle(on: client, onEvent: onEvent)
                }
                // Cancelled while entering: the handler had nothing to stop yet.
                if Task.isCancelled {
                    await interruptIdle()
                }
                switch await awaitIdleEnd() {
                case .interrupted:
                    return
                case .expired:
                    log.info("idle re-issue")
                    continue
                case .failed(let error):
                    throw error
                }
            }
        } onCancel: {
            Task { await self.interruptIdle() }
        }
    }

    /// Chained step: confirm IDLE is offered, send it, and park the wait in
    /// a side task. `idleTask` is set before the step completes so that the
    /// next chained command sees it and stops it first.
    private func enterIdle(
        on client: IMAPClient,
        onEvent: @escaping @Sendable (IMAPClient.IdleEvent) -> Void
    ) async throws {
        if await client.capabilities == nil {
            try await client.fetchCapabilities()
        }
        guard await client.supportsIdle else { throw MailSessionError.idleUnsupported }
        // IDLE watches the selected mailbox, and the watch is for new mail:
        // a command that browsed Sent or Spam must not leave the idle
        // parked there.
        if await client.selectedMailbox != "INBOX" {
            _ = try await client.selectInbox()
        }
        try await client.beginIdle()
        idleInterrupted = false
        idleTask = Task { try await client.awaitIdle(onEvent: onEvent) }
        idleTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.idleReissueAfter)
            guard !Task.isCancelled else { return }
            await self?.stopIdle(on: client, interrupting: false)
        }
        log.info("idle start")
    }

    private func awaitIdleEnd() async -> IdleOutcome {
        guard let task = idleTask else { return .interrupted }
        let result = await task.result
        finishIdle(task)
        switch result {
        case .success:
            return idleInterrupted ? .interrupted : .expired
        case .failure(let error):
            // A failure while being stopped was either our own drop (DONE
            // unanswered) or a coincidence; either way the caller re-enters
            // and the next command reconnects.
            if idleInterrupted { return .interrupted }
            log.error("idle failed: \(error.localizedDescription, privacy: .public)")
            await close()
            return .failed(error)
        }
    }

    /// Ends the idle wait ahead of a command or `close`. No-op when not idling.
    private func interruptIdle() async {
        guard idleTask != nil, let client else { return }
        await stopIdle(on: client, interrupting: true)
    }

    /// DONE, then wait for the tagged OK that ends `awaitIdle`. A server
    /// that never answers gets its socket dropped after a grace period —
    /// that is the only way out of the blocked read.
    private func stopIdle(on client: IMAPClient, interrupting: Bool) async {
        guard let task = idleTask else { return }
        if interrupting {
            idleInterrupted = true
        }
        log.info("idle stop")
        try? await client.stopIdle()
        let grace = Task {
            try? await Task.sleep(for: Self.idleStopGrace)
            guard !Task.isCancelled else { return }
            log.error("idle: DONE unanswered, dropping the connection")
            await client.dropConnection()
        }
        let result = await task.result
        grace.cancel()
        finishIdle(task)
        switch result {
        case .success:
            lastUsedAt = Date()
        case .failure:
            // Dead socket — do not hand it to the next command.
            await client.dropConnection()
            if self.client === client {
                self.client = nil
            }
        }
    }

    private func finishIdle(_ task: Task<Void, Error>) {
        idleTimer?.cancel()
        idleTimer = nil
        if idleTask == task {
            idleTask = nil
        }
    }
}
