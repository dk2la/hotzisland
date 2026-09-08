import AppKit
import Foundation
import Observation
import OSLog

/// "Email" module service: single IMAP account, 90s poll, stateless
/// sessions (connect → login → select → search → fetch → logout). Errors
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
    private(set) var lastRefresh: Date?
    private(set) var lastError: String?

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
    private static let messageLimit = 30

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
            lastError = "Keychain: \(error.localizedDescription)"
            return
        }
        dropSessions()
        config = newConfig
        if let data = try? JSONEncoder().encode(newConfig) {
            defaults.set(data, forKey: EmailAccountConfig.defaultsKey)
        }
        messages = []
        unreadCount = 0
        lastError = nil
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
                self?.refresh()
                try? await Task.sleep(for: .seconds(90))
            }
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
            defer { self?.refreshTask = nil }
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
                self.lastRefresh = Date()
                self.lastError = nil
                self.log.info("refreshed exists=\(result.0, privacy: .public) unread=\(result.1, privacy: .public)")
                self.prefetchBodies()
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
                self.lastError = error.localizedDescription
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
        var text = body.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Table-heavy marketing HTML can flatten to nothing; the real
        // renderer still extracts readable text, and the list preview and
        // the reply quote both need it.
        if text.isEmpty, let html = body.html {
            text = EmailHTMLRenderer.render(html)?.string
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
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
