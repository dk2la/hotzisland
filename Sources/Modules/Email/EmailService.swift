import AppKit
import Foundation
import Observation
import OSLog

/// "Email" module service: single IMAP account on two long-lived sessions.
/// New mail arrives by IMAP IDLE when the server offers it; the 90s poll
/// is the fallback (and the only refresh source while not idling). Errors
/// keep the last good message list on screen.
@MainActor
@Observable
final class EmailService {
    private(set) var config: EmailAccountConfig?
    private(set) var connection: MailConnectionState = .offline
    private(set) var unreadCount = 0
    private(set) var messages: [EmailMessage] = []
    private(set) var openMessage: EmailMessage?
    private(set) var isLoadingBody = false

    /// Compose state — a Gmail-like To/Subject/Body form used for both
    /// replies (prefilled, threaded) and new mail. It lives here, not in
    /// the view, so collapsing the panel mid-sentence keeps the draft.
    private(set) var isComposeOpen = false
    var composeTo = ""
    var composeSubject = ""
    var draft = ""
    @ObservationIgnored private var composeInReplyTo: String?
    @ObservationIgnored private var composeReferences: [String] = []
    private(set) var isSending = false
    private(set) var didSend = false
    private(set) var sendError: String?

    /// Server-side search. State lives here so the panel header (which owns
    /// the search toggle) and the module view share it.
    private(set) var isSearchOpen = false
    var searchQuery = ""
    private(set) var searchResults: [EmailMessage]?
    private(set) var isSearching = false

    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "email")
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let vault = SecretVault(service: EmailAccountConfig.keychainService)
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    /// Two long-lived IMAP connections: one for the 90s poll, one for what
    /// the user just clicked. Reconnecting per action made opening a message
    /// take seconds; sharing a single connection would queue the click
    /// behind a poll that is streaming 30 message headers.
    @ObservationIgnored private var pollSession: MailSession?
    @ObservationIgnored private var userSession: MailSession?
    /// The IDLE loop on the poll session; nil while polling.
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    /// Bumped whenever the loop is (re)started so a finished loop only
    /// clears its own handle, never a successor's.
    @ObservationIgnored private var idleGeneration = 0
    /// nil until the server has answered CAPABILITY; false pins the poll.
    @ObservationIgnored private var idleSupported: Bool?
    /// An idle event landed while a refresh was in flight — run one more.
    @ObservationIgnored private var refreshAgain = false
    private static let messageLimit = 30
    private static let pollInterval: Duration = .seconds(90)
    private static let idleRetryDelay: Duration = .seconds(5)
    /// Commands come in bursts (a refresh, then its body prefetches); a
    /// short pause before re-entering IDLE keeps that burst on one IDLE/DONE
    /// cycle instead of one per command.
    private static let idleReenterDelay: Duration = .seconds(1)

    init() {
        if let data = defaults.data(forKey: EmailAccountConfig.defaultsKey),
           let stored = try? JSONDecoder().decode(EmailAccountConfig.self, from: data) {
            config = stored
        }
        startPolling()
        log.info("configured=\(self.config != nil, privacy: .public)")
    }

    // MARK: - Account

    func saveAccount(_ newConfig: EmailAccountConfig, password: String) {
        do {
            try vault.set(password, account: newConfig.email)
        } catch {
            log.error("keychain write failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        dropSessions()
        idleSupported = nil
        config = newConfig
        if let data = try? JSONEncoder().encode(newConfig) {
            defaults.set(data, forKey: EmailAccountConfig.defaultsKey)
        }
        messages = []
        unreadCount = 0
        log.info("account saved host=\(newConfig.imapHost, privacy: .public)")
        startPolling()
        refresh()
    }

    func removeAccount() {
        if let config {
            vault.delete(account: config.email)
        }
        dropSessions()
        config = nil
        defaults.removeObject(forKey: EmailAccountConfig.defaultsKey)
        messages = []
        unreadCount = 0
        openMessage = nil
        connection = .offline
        pollTask?.cancel()
        log.info("account removed")
    }

    /// Standalone connectivity probe for the setup form.
    nonisolated static func testConnection(
        _ config: EmailAccountConfig,
        password: String
    ) async -> Result<Void, Error> {
        let client = IMAPClient(host: config.imapHost, port: config.imapPort)
        do {
            try await client.connect()
            try await client.login(user: config.email, password: password)
            _ = try await client.selectInbox()
            await client.logout()
            return .success(())
        } catch {
            await client.logout()
            return .failure(error)
        }
    }

    // MARK: - Refresh

    private func startPolling() {
        pollTask?.cancel()
        guard config != nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                // While IDLE is running the server pushes changes; the
                // timer only fills in when it is not.
                if self?.idleTask == nil {
                    self?.refresh()
                }
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    // MARK: - IDLE

    /// Starts the IDLE loop on the poll session unless it is already running
    /// or the server is known not to offer IDLE. Each `MailSession.idle`
    /// returns when a command (refresh, markRead, prefetch) took the
    /// connection; the loop simply re-enters, queued behind that command.
    private func startIdling() {
        guard idleTask == nil, idleSupported != false, let session = activePollSession() else { return }
        idleGeneration += 1
        let generation = idleGeneration
        // Built here, not inside the loop task: a weak `self` captured
        // through another closure is a var and cannot cross into the
        // @Sendable event callback.
        let onEvent: @Sendable (IMAPClient.IdleEvent) -> Void = { [weak self] event in
            Task { @MainActor in
                self?.handleIdleEvent(event)
            }
        }
        idleTask = Task { [weak self] in
            defer {
                if let self, self.idleGeneration == generation {
                    self.idleTask = nil
                }
            }
            while !Task.isCancelled {
                do {
                    try await session.idle(onEvent: onEvent)
                    guard !Task.isCancelled else { return }
                    self?.idleSupported = true
                    try? await Task.sleep(for: Self.idleReenterDelay)
                } catch MailSessionError.idleUnsupported {
                    self?.idleSupported = false
                    self?.log.info("idle unsupported, polling every \(Self.pollInterval.milliseconds / 1000, privacy: .public)s")
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.log.error("idle failed: \(error.localizedDescription, privacy: .public)")
                    try? await Task.sleep(for: Self.idleRetryDelay)
                    guard !Task.isCancelled else { return }
                    // refresh's run reconnects; the loop re-enters after it.
                    self?.refresh()
                }
            }
        }
    }

    private func handleIdleEvent(_ event: IMAPClient.IdleEvent) {
        log.info("idle event \(event.description, privacy: .public)")
        if refreshTask != nil {
            refreshAgain = true
        } else {
            refresh()
        }
    }

    private func accountPassword() -> String? {
        config.flatMap { vault.secret(account: $0.email) }
    }

    private func makeSession() -> MailSession? {
        guard let config, let password = accountPassword() else { return nil }
        return MailSession(
            host: config.imapHost,
            port: config.imapPort,
            user: config.email,
            password: password
        )
    }

    /// Background polling connection.
    private func activePollSession() -> MailSession? {
        if let pollSession { return pollSession }
        pollSession = makeSession()
        return pollSession
    }

    /// Foreground connection for taps: opening a message, marking it read.
    private func activeUserSession() -> MailSession? {
        if let userSession { return userSession }
        userSession = makeSession()
        return userSession
    }

    private func dropSessions() {
        prefetchTask?.cancel()
        prefetchTask = nil
        idleTask?.cancel()
        idleTask = nil
        idleGeneration += 1
        let open = [pollSession, userSession].compactMap { $0 }
        pollSession = nil
        userSession = nil
        guard !open.isEmpty else { return }
        Task {
            for session in open {
                await session.close()
            }
        }
    }

    func refresh() {
        guard refreshTask == nil, config != nil else { return }
        guard accountPassword() != nil else {
            connection = .failed("No password in Keychain")
            return
        }
        guard let session = activePollSession() else { return }
        connection = messages.isEmpty ? .connecting : connection
        let limit = Self.messageLimit
        refreshTask = Task { [weak self] in
            defer {
                self?.refreshTask = nil
                if self?.refreshAgain == true {
                    self?.refreshAgain = false
                    self?.refresh()
                }
            }
            do {
                let result = try await session.run { client -> (Int, Int, [EmailMessage]) in
                    // SELECT again: EXISTS moves as mail arrives on a
                    // connection we are keeping open across polls.
                    let exists = try await client.selectInbox()
                    let unread = try await client.searchUnseenCount()
                    let fetched = try await client.fetchHeaders(exists: exists, limit: limit)
                    return (exists, unread, fetched)
                }
                guard let self, !Task.isCancelled else { return }
                self.unreadCount = result.1
                // A poll must not throw away bodies that are already in
                // memory — that made a message lag again after every 90s.
                var merged = result.2
                let known = Dictionary(uniqueKeysWithValues: self.messages.map { ($0.uid, $0) })
                for index in merged.indices {
                    if let cached = known[merged[index].uid], cached.bodyPlain != nil {
                        merged[index].bodyPlain = cached.bodyPlain
                        merged[index].bodyHTML = cached.bodyHTML
                        merged[index].references = cached.references
                    }
                }
                self.messages = merged
                self.connection = .online
                self.log.info("refreshed exists=\(result.0, privacy: .public) unread=\(result.1, privacy: .public)")
                self.prefetchBodies()
                self.startIdling()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.connection = .failed(error.localizedDescription)
                self.log.error("refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// "18811" reads as noise, not information — the badge caps at 99+.
    var unreadBadge: String? {
        guard unreadCount > 0 else { return nil }
        return unreadCount > 99 ? "99+" : "\(unreadCount)"
    }

    // MARK: - Search

    func toggleSearch() {
        isSearchOpen.toggle()
        if !isSearchOpen {
            clearSearch()
        }
    }

    /// Back to the live inbox list; the search row stays open.
    func clearSearch() {
        searchQuery = ""
        searchResults = nil
    }

    func runSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isSearching, let session = activeUserSession() else { return }
        isSearching = true
        let limit = Self.messageLimit
        Task { [weak self] in
            do {
                let found = try await session.run { client -> [EmailMessage] in
                    let uids = try await client.searchUIDs(query: query, limit: limit)
                    return try await client.fetchHeaders(uids: uids)
                }
                guard let self else { return }
                self.searchResults = found
                self.log.info("search hits=\(found.count, privacy: .public)")
            } catch {
                guard let self else { return }
                self.searchResults = []
                self.log.error("search failed: \(error.localizedDescription, privacy: .public)")
            }
            self?.isSearching = false
        }
    }

    // MARK: - Message actions

    /// Moves the message out of INBOX. Optimistic: the row disappears at
    /// once; a failed move logs, surfaces, and the next poll resyncs.
    func archive(_ message: EmailMessage) {
        guard let session = activeUserSession() else { return }
        if message.isUnread {
            unreadCount = max(0, unreadCount - 1)
        }
        messages.removeAll { $0.uid == message.uid }
        searchResults?.removeAll { $0.uid == message.uid }
        if openMessage?.uid == message.uid {
            closeMessage()
        }
        let uid = message.uid
        let folders = archiveFolders
        Task { [weak self] in
            do {
                try await session.run { client in
                    var lastError: Error = MailError.badResponse("no archive folder")
                    for folder in folders {
                        do {
                            try await client.move(uid: uid, to: folder)
                            return
                        } catch {
                            lastError = error
                        }
                    }
                    throw lastError
                }
                self?.log.info("archived uid=\(uid, privacy: .public)")
            } catch {
                guard let self else { return }
                self.log.error("archive failed: \(error.localizedDescription, privacy: .public)")
                self.refresh()
            }
        }
    }

    /// Candidate destinations, most likely first. Gmail files everything in
    /// All Mail; the rest of the world calls the folder Archive.
    private var archiveFolders: [String] {
        switch EmailProvider(rawValue: config?.presetID ?? "") {
        case .gmail: ["[Gmail]/All Mail", "Archive"]
        default: ["Archive", "[Gmail]/All Mail", "Archived"]
        }
    }

    /// Deep link into Mail.app by Message-ID, with a bare mailto: fallback.
    func openInMailApp() {
        guard let message = openMessage else { return }
        if let raw = message.messageID?
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            .addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
            let url = URL(string: "message://%3C\(raw)%3E") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "mailto:") {
            NSWorkspace.shared.open(url)
        }
    }

    func open(_ message: EmailMessage) {
        if openMessage?.uid != message.uid {
            resetComposer()
        }
        openMessage = message
        if message.bodyPlain == nil {
            loadBody(for: message)
        }
        if message.isUnread {
            markRead(message)
        }
    }

    func closeMessage() {
        openMessage = nil
        resetComposer()
    }

    private func resetComposer() {
        // A reply draft belongs to the previous message; a new-mail draft
        // survives navigation.
        if composeInReplyTo != nil {
            composeTo = ""
            composeSubject = ""
            draft = ""
            composeInReplyTo = nil
            composeReferences = []
        }
        sendError = nil
        didSend = false
    }

    private func loadBody(for message: EmailMessage) {
        guard let session = activeUserSession() else { return }
        isLoadingBody = true
        let uid = message.uid
        let part = message.textPart
        let startedAt = ContinuousClock.now
        Task { [weak self] in
            do {
                let body = try await session.run { try await $0.fetchBody(uid: uid, part: part) }
                let elapsed = ContinuousClock.now - startedAt
                self?.log.info("body ready in \(elapsed.milliseconds, privacy: .public) ms")
                self?.store(body, uid: uid)
            } catch {
                // Leave bodyPlain nil so the next open (or prefetch) retries.
                self?.log.error("body load failed: \(error.localizedDescription, privacy: .public)")
            }
            self?.isLoadingBody = false
        }
    }

    /// Puts a fetched body into the list and, when relevant, the open view.
    private func store(_ body: MessageBody, uid: UInt32) {
        // An empty string still marks the body as fetched (nil means "not
        // loaded yet"); HTML-only mail is read through the web view, so no
        // second flattening pass — that one used AppKit's WebKit-backed
        // importer, which fetches remote resources with no network block.
        let text = body.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if var open = openMessage, open.uid == uid {
            open.bodyPlain = text
            open.bodyHTML = body.html
            open.references = body.references
            openMessage = open
        }
        if let index = messages.firstIndex(where: { $0.uid == uid }) {
            messages[index].bodyPlain = text
            messages[index].bodyHTML = body.html
            messages[index].references = body.references
        }
    }

    /// Downloads bodies the list does not have yet, newest first, on the
    /// background connection. Opening a message then shows it instantly from
    /// memory instead of paying network round trips while the user stares
    /// at a placeholder.
    private func prefetchBodies() {
        guard prefetchTask == nil, let session = activePollSession() else { return }
        let pending = messages
            .filter { $0.bodyPlain == nil }
            .map { (uid: $0.uid, part: $0.textPart) }
        guard !pending.isEmpty else { return }
        prefetchTask = Task { [weak self] in
            defer { self?.prefetchTask = nil }
            var fetched = 0
            for item in pending {
                guard !Task.isCancelled else { return }
                // A message may have been opened (and loaded) meanwhile.
                guard self?.messages.first(where: { $0.uid == item.uid })?.bodyPlain == nil else { continue }
                guard let body = try? await session.run({
                    try await $0.fetchBody(uid: item.uid, part: item.part)
                }) else { continue }
                self?.store(body, uid: item.uid)
                fetched += 1
            }
            if fetched > 0 {
                self?.log.info("prefetched bodies=\(fetched, privacy: .public)")
            }
        }
    }

    // MARK: - Compose

    /// Reply to the open message: To and Subject prefilled, threading
    /// headers carried over. Re-opening the same reply keeps its draft.
    func startReply() {
        guard let message = openMessage else { return }
        if composeInReplyTo != message.messageID || composeTo != message.fromAddress {
            composeTo = message.fromAddress
            composeSubject = MailComposer.replySubject(message.subject)
            draft = ""
            composeInReplyTo = message.messageID
            composeReferences = message.references
        }
        sendError = nil
        didSend = false
        isComposeOpen = true
    }

    /// Blank message. An unsent new-mail draft survives closing the form;
    /// only leftovers of a reply are cleared.
    func startNewMail() {
        if composeInReplyTo != nil {
            composeTo = ""
            composeSubject = ""
            draft = ""
            composeInReplyTo = nil
            composeReferences = []
        }
        sendError = nil
        didSend = false
        isComposeOpen = true
    }

    /// Back: the form closes, the draft stays.
    func closeCompose() {
        isComposeOpen = false
    }

    /// Cancel: the draft is gone.
    func discardCompose() {
        isComposeOpen = false
        composeTo = ""
        composeSubject = ""
        draft = ""
        composeInReplyTo = nil
        composeReferences = []
        sendError = nil
    }

    var canSendCompose: Bool {
        !isSending
            && composeTo.trimmingCharacters(in: .whitespaces).contains("@")
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func sendCompose() {
        guard let config, canSendCompose else { return }
        guard let password = accountPassword() else {
            sendError = "No password in Keychain"
            return
        }
        let mail = OutgoingMail(
            from: config.email,
            to: composeTo.trimmingCharacters(in: .whitespaces),
            subject: composeSubject.trimmingCharacters(in: .whitespacesAndNewlines),
            body: draft.trimmingCharacters(in: .whitespacesAndNewlines),
            inReplyTo: composeInReplyTo,
            references: composeReferences
        )
        isSending = true
        sendError = nil
        Task { [weak self] in
            let client = SMTPClient(
                host: config.smtpHost,
                port: config.smtpPort,
                usesSTARTTLS: config.smtpUsesSTARTTLS
            )
            do {
                try await client.connect()
                try await client.login(user: config.email, password: password)
                try await client.send(mail)
                await client.quit()
                guard let self else { return }
                self.isSending = false
                self.didSend = true
                self.discardCompose()
                self.log.info("mail sent reply=\(mail.inReplyTo != nil, privacy: .public)")
            } catch {
                await client.quit()
                guard let self else { return }
                self.isSending = false
                self.sendError = error.localizedDescription
                self.log.error("send failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Optimistic local flip, then the server call.
    func markRead(_ message: EmailMessage) {
        guard let session = activePollSession() else { return }
        if let index = messages.firstIndex(where: { $0.uid == message.uid }), messages[index].isUnread {
            messages[index].isUnread = false
            unreadCount = max(0, unreadCount - 1)
        }
        if var open = openMessage, open.uid == message.uid {
            open.isUnread = false
            openMessage = open
        }
        let uid = message.uid
        Task {
            // Failure is fine: the next poll reconciles the flag.
            try? await session.run { try await $0.markSeen(uid: uid) }
        }
    }
}
