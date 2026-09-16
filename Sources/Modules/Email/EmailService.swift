import AppKit
import Foundation
import Observation
import OSLog

/// What one refresh brings back from the poll connection.
private struct RefreshResult: Sendable {
    var folders: IMAPClient.SpecialFolders
    var isGmail: Bool
    var inboxExists: Int
    var unread: Int
    var messages: [EmailMessage]
}

/// "Email" module service: single IMAP account on two long-lived sessions.
/// New mail arrives by IMAP IDLE when the server offers it; the 90s poll
/// is the fallback (and the only refresh source while not idling). Errors
/// keep the last good message list on screen.
///
/// The inbox is split into Gmail-like sections (`Mailbox`). Each section
/// keeps its own list; a message carries the IMAP folder it was listed
/// from, and everything that touches a message on the server — body,
/// flags, move — selects that folder first, because a UID only means
/// something inside one folder. The unread badge, IDLE and search stay
/// INBOX affairs whatever section is showing.
@MainActor
@Observable
final class EmailService {
    private(set) var config: EmailAccountConfig?
    private(set) var connection: MailConnectionState = .offline
    private(set) var unreadCount = 0
    /// The section on screen; remembered across launches.
    private(set) var selectedMailbox: Mailbox
    /// Sections the server can serve, in display order. Primary and
    /// Starred always; the rest once the first refresh has listed the
    /// folders.
    private(set) var availableMailboxes: [Mailbox] = [.primary, .starred]
    /// One list per section. The messages carry their fetched bodies, so
    /// this doubles as the body cache — keyed by section, each message by
    /// its (folder, UID).
    private var messagesByMailbox: [Mailbox: [EmailMessage]] = [:]
    /// When each section's list was last fetched; missing = never.
    @ObservationIgnored private var refreshedAt: [Mailbox: Date] = [:]
    /// The selected section's list.
    var messages: [EmailMessage] { messagesByMailbox[selectedMailbox] ?? [] }

    /// Every cached header across the sections, newest first, each message
    /// once — what the assistant searches without touching the server.
    var cachedMessages: [EmailMessage] {
        var seen = Set<MessageKey>()
        return messagesByMailbox.values
            .flatMap { $0 }
            .filter { seen.insert($0.key).inserted }
            .sorted { $0.date > $1.date }
    }

    /// Opens the search row with a query and runs it — the assistant's
    /// way of handing a search to the user.
    func search(_ query: String) {
        if !isSearchOpen { isSearchOpen = true }
        searchQuery = query
        runSearch()
    }
    /// Folder roles as the server reported them; nil until the first
    /// refresh asked.
    @ObservationIgnored private var specialFolders: IMAPClient.SpecialFolders?
    @ObservationIgnored private var isGmail = false
    private(set) var openMessage: EmailMessage?
    private(set) var isLoadingBody = false

    /// Compose state — a Gmail-like To/Subject/Body form used for both
    /// replies (prefilled, threaded) and new mail. It lives here, not in
    /// the view, so collapsing the panel mid-sentence keeps the draft.
    private(set) var isComposeOpen = false
    var composeTo = ""
    /// Comma-separated, like the To field.
    var composeCc = ""
    var composeSubject = ""
    var draft = ""
    /// How the form was seeded; nil for new mail.
    private(set) var composeMode: ReplyMode?
    /// The message the draft was seeded from, so re-opening it keeps the
    /// draft and opening another one clears it.
    @ObservationIgnored private var composeSourceKey: MessageKey?
    @ObservationIgnored private var composeInReplyTo: String?
    @ObservationIgnored private var composeReferences: [String] = []
    /// The forwarded block currently at the end of the draft, if any.
    @ObservationIgnored private var composeQuote: String?
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
    /// A section's list older than this is fetched again on switching to it.
    private static let staleAfter: TimeInterval = 120
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
        selectedMailbox = defaults.string(forKey: Mailbox.defaultsKey).flatMap(Mailbox.init) ?? .primary
        if config != nil {
            loadCachedLists()
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
        resetLists()
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
        resetLists()
        openMessage = nil
        connection = .offline
        pollTask?.cancel()
        log.info("account removed")
    }

    /// Forgets everything fetched for the previous account, folder roles
    /// included — another server names its folders differently.
    private func resetLists() {
        messagesByMailbox = [:]
        try? FileManager.default.removeItem(at: Self.cacheURL)
        refreshedAt = [:]
        specialFolders = nil
        isGmail = false
        availableMailboxes = [.primary, .starred]
        unreadCount = 0
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
                    // A body prefetch is a burst of commands on this very
                    // session; re-entering IDLE between them would DONE/IDLE
                    // once per message. Let the burst finish first.
                    while let prefetch = self?.prefetchTask, !Task.isCancelled {
                        await prefetch.value
                    }
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
        // INBOX changed: its sections are due a fetch on the next visit
        // even if the refresh below only covers the one on screen.
        refreshedAt[.primary] = nil
        refreshedAt[.starred] = nil
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
        let mailbox = selectedMailbox
        let knownFolders = specialFolders
        refreshTask = Task { [weak self] in
            defer {
                self?.refreshTask = nil
                if self?.refreshAgain == true {
                    self?.refreshAgain = false
                    self?.refresh()
                }
            }
            do {
                let result = try await session.run { client -> RefreshResult in
                    // Folder roles are asked once per account; every
                    // connection to the same server answers the same.
                    let folders: IMAPClient.SpecialFolders
                    if let knownFolders {
                        folders = knownFolders
                    } else {
                        folders = try await client.listSpecialUse()
                    }
                    let gmail = await client.isGmail
                    // INBOX first, whatever section is showing: the unread
                    // badge is about the inbox. SELECT again: EXISTS moves
                    // as mail arrives on a connection kept open across polls.
                    let exists = try await client.selectInbox()
                    let unread = try await client.searchUnseenCount()
                    let fetched = try await Self.fetchList(
                        mailbox, on: client, folders: folders, isGmail: gmail, inboxExists: exists, limit: limit
                    )
                    return RefreshResult(
                        folders: folders, isGmail: gmail, inboxExists: exists, unread: unread, messages: fetched
                    )
                }
                guard let self, !Task.isCancelled else { return }
                self.adoptFolders(result.folders, isGmail: result.isGmail)
                self.unreadCount = result.unread
                self.store(list: result.messages, for: mailbox)
                self.refreshedAt[mailbox] = Date()
                self.connection = .online
                self.log.info("refreshed \(mailbox.rawValue, privacy: .public) exists=\(result.inboxExists, privacy: .public) unread=\(result.unread, privacy: .public) n=\(result.messages.count, privacy: .public)")
                self.prefetchBodies()
                self.startIdling()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.connection = .failed(error.localizedDescription)
                self.log.error("refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The messages of one section. A folder-backed section (Sent, Spam,
    /// Gmail's Important) is selected and its newest messages fetched; a
    /// slice of INBOX (Primary, Starred) is picked out by UID SEARCH with
    /// INBOX selected, which `refresh` has just done.
    nonisolated private static func fetchList(
        _ mailbox: Mailbox,
        on client: IMAPClient,
        folders: IMAPClient.SpecialFolders,
        isGmail: Bool,
        inboxExists: Int,
        limit: Int
    ) async throws -> [EmailMessage] {
        switch mailbox {
        case .primary:
            guard isGmail else {
                return try await client.fetchHeaders(exists: inboxExists, limit: limit)
            }
            // Gmail: the Primary tab only. Should the server balk at the
            // extension, the whole inbox is the honest fallback.
            do {
                // Bounded to recent mail: an unbounded category search
                // walks the whole mailbox on Gmail's side and takes seconds.
                return try await client.fetchHeaders(searching: "X-GM-RAW \"category:primary newer_than:90d\"", limit: limit)
            } catch MailError.badResponse {
                return try await client.fetchHeaders(exists: inboxExists, limit: limit)
            }
        case .starred:
            return try await client.fetchHeaders(searching: "FLAGGED", limit: limit)
        case .important, .sent, .spam:
            guard let folder = folder(for: mailbox, in: folders) else { return [] }
            let exists = try await client.select(folder)
            return try await client.fetchHeaders(exists: exists, limit: limit)
        }
    }

    /// The IMAP folder behind a section; nil when the server has none.
    nonisolated private static func folder(for mailbox: Mailbox, in folders: IMAPClient.SpecialFolders) -> String? {
        switch mailbox {
        case .primary, .starred: "INBOX"
        case .important: folders.important
        case .sent: folders.sent
        case .spam: folders.junk
        }
    }

    /// Settles which sections the server can serve. Important is a Gmail
    /// label with no equivalent elsewhere; Sent and Spam need a folder.
    private func adoptFolders(_ folders: IMAPClient.SpecialFolders, isGmail: Bool) {
        specialFolders = folders
        self.isGmail = isGmail
        var available: [Mailbox] = [.primary, .starred]
        if isGmail, folders.important != nil {
            available.append(.important)
        }
        if folders.sent != nil {
            available.append(.sent)
        }
        if folders.junk != nil {
            available.append(.spam)
        }
        availableMailboxes = available
        // A remembered section this account cannot serve.
        if !available.contains(selectedMailbox) {
            select(.primary)
        }
    }

    /// Switches the section on screen. Its list is fetched again when it
    /// was never fetched, came back empty, or has gone stale.
    func select(_ mailbox: Mailbox) {
        guard mailbox != selectedMailbox else { return }
        selectedMailbox = mailbox
        defaults.set(mailbox.rawValue, forKey: Mailbox.defaultsKey)
        // Search results are INBOX hits; they do not belong to the new section.
        if searchResults != nil {
            clearSearch()
        }
        guard isStale(mailbox) else { return }
        if refreshTask != nil {
            refreshAgain = true
        } else {
            refresh()
        }
    }

    private func isStale(_ mailbox: Mailbox) -> Bool {
        guard let fetchedAt = refreshedAt[mailbox], !(messagesByMailbox[mailbox] ?? []).isEmpty else {
            return true
        }
        return Date().timeIntervalSince(fetchedAt) > Self.staleAfter
    }

    /// Puts a freshly fetched list in place. A poll must not throw away
    /// bodies that are already in memory — that made a message lag again
    /// after every 90s. The same message shows up in several sections
    /// (a starred inbox mail is in Primary and Starred), so bodies are
    /// looked up across all of them by folder + UID.
    private func store(list: [EmailMessage], for mailbox: Mailbox) {
        var merged = list
        let known = bodiesInMemory()
        for index in merged.indices {
            if let cached = known[merged[index].key] {
                merged[index].bodyPlain = cached.bodyPlain
                merged[index].bodyHTML = cached.bodyHTML
                merged[index].references = cached.references
            }
        }
        messagesByMailbox[mailbox] = merged
        saveCachedLists()
    }

    // MARK: - Header cache

    /// The last fetched headers of every section, so a launch shows mail
    /// at once and "Checking" only ever replaces a list, never an empty
    /// panel. Headers only — bodies are re-fetched — so the file stays at
    /// a few tens of kilobytes; one read at launch, one write per refresh.
    private static let cacheURL: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("com.dk2la.hotzisland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mail-headers.json")
    }()

    private func loadCachedLists() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let lists = try? JSONDecoder().decode([Mailbox: [EmailMessage]].self, from: data)
        else { return }
        messagesByMailbox = lists
        log.info("header cache loaded sections=\(lists.count, privacy: .public)")
    }

    private func saveCachedLists() {
        var headersOnly = messagesByMailbox
        for mailbox in headersOnly.keys {
            headersOnly[mailbox] = headersOnly[mailbox]?.map { message in
                var copy = message
                copy.bodyPlain = nil
                copy.bodyHTML = nil
                return copy
            }
        }
        let url = Self.cacheURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(headersOnly) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Every message in memory whose body is loaded, by folder + UID.
    private func bodiesInMemory() -> [MessageKey: EmailMessage] {
        var known: [MessageKey: EmailMessage] = [:]
        for list in messagesByMailbox.values {
            for message in list where message.bodyPlain != nil {
                known[message.key] = message
            }
        }
        return known
    }

    /// The in-memory copy of a message, from whichever section holds it.
    private func messageInMemory(_ key: MessageKey) -> EmailMessage? {
        for list in messagesByMailbox.values {
            if let found = list.first(where: { $0.key == key }) { return found }
        }
        return nil
    }

    /// Applies an edit to every in-memory copy of a message.
    private func updateEverywhere(_ key: MessageKey, _ edit: (inout EmailMessage) -> Void) {
        for mailbox in messagesByMailbox.keys {
            guard let index = messagesByMailbox[mailbox]?.firstIndex(where: { $0.key == key }) else { continue }
            if var message = messagesByMailbox[mailbox]?[index] {
                edit(&message)
                messagesByMailbox[mailbox]?[index] = message
            }
        }
        if var open = openMessage, open.key == key {
            edit(&open)
            openMessage = open
        }
    }

    /// Whether a message was listed from the Sent folder — its row shows
    /// the recipient rather than the sender.
    func isSentMessage(_ message: EmailMessage) -> Bool {
        guard let sent = specialFolders?.sent else { return false }
        return message.mailbox == sent
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
                // Search covers the inbox, whatever section is showing.
                let found = try await session.run(in: "INBOX") { client -> [EmailMessage] in
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

    /// Whether "archive" means anything for a message: it must still be in
    /// the inbox. Sent and Spam mail is not there to begin with; Gmail's
    /// Important is a label on inbox mail, so it qualifies.
    func canArchive(_ message: EmailMessage) -> Bool {
        if message.mailbox == "INBOX" { return true }
        if let important = specialFolders?.important, message.mailbox == important { return true }
        return false
    }

    /// Moves the message out of INBOX. Optimistic: the row disappears at
    /// once; a failed move logs, surfaces, and the next poll resyncs.
    func archive(_ message: EmailMessage) {
        guard canArchive(message), let session = activeUserSession() else { return }
        if message.isUnread, message.mailbox == "INBOX" {
            unreadCount = max(0, unreadCount - 1)
        }
        let key = message.key
        for mailbox in messagesByMailbox.keys {
            messagesByMailbox[mailbox]?.removeAll { $0.key == key }
        }
        searchResults?.removeAll { $0.key == key }
        if openMessage?.key == key {
            closeMessage()
        }
        let messageID = message.messageID
        let folders = archiveFolders
        Task { [weak self] in
            do {
                try await session.run(in: "INBOX") { client in
                    // Listed from another folder (Gmail's Important): the
                    // inbox copy has a UID of its own — find it by Message-ID.
                    let uid: UInt32
                    if key.mailbox == "INBOX" {
                        uid = key.uid
                    } else {
                        guard let messageID, let found = try await client.findUID(messageID: messageID) else {
                            throw MailError.badResponse("message is not in INBOX")
                        }
                        uid = found
                    }
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
                self?.log.info("archived uid=\(key.uid, privacy: .public) from=\(key.mailbox, privacy: .public)")
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
        if openMessage?.key != message.key {
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
        if composeSourceKey != nil {
            clearDraft()
        }
        sendError = nil
        didSend = false
    }

    private func clearDraft() {
        composeTo = ""
        composeCc = ""
        composeSubject = ""
        draft = ""
        composeMode = nil
        composeSourceKey = nil
        composeInReplyTo = nil
        composeReferences = []
        composeQuote = nil
    }

    private func loadBody(for message: EmailMessage) {
        guard let session = activeUserSession() else { return }
        isLoadingBody = true
        let key = message.key
        let part = message.textPart
        let startedAt = ContinuousClock.now
        Task { [weak self] in
            do {
                let body = try await session.run(in: key.mailbox) { try await $0.fetchBody(uid: key.uid, part: part) }
                let elapsed = ContinuousClock.now - startedAt
                self?.log.info("body ready in \(elapsed.milliseconds, privacy: .public) ms")
                self?.store(body, key: key)
            } catch {
                // Leave bodyPlain nil so the next open (or prefetch) retries.
                self?.log.error("body load failed: \(error.localizedDescription, privacy: .public)")
            }
            self?.isLoadingBody = false
        }
    }

    /// Puts a fetched body into every list holding the message and, when
    /// relevant, the open view.
    private func store(_ body: MessageBody, key: MessageKey) {
        // An empty string still marks the body as fetched (nil means "not
        // loaded yet"); HTML-only mail is read through the web view, so no
        // second flattening pass — that one used AppKit's WebKit-backed
        // importer, which fetches remote resources with no network block.
        let text = body.text.trimmingCharacters(in: .whitespacesAndNewlines)
        updateEverywhere(key) { message in
            message.bodyPlain = text
            message.bodyHTML = body.html
            message.references = body.references
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
            .map { (key: $0.key, part: $0.textPart) }
        guard !pending.isEmpty else { return }
        prefetchTask = Task { [weak self] in
            defer { self?.prefetchTask = nil }
            var fetched = 0
            for item in pending {
                guard !Task.isCancelled else { return }
                // A message may have been opened (and loaded) meanwhile.
                guard self?.messageInMemory(item.key)?.bodyPlain == nil else { continue }
                guard let body = try? await session.run(in: item.key.mailbox, {
                    try await $0.fetchBody(uid: item.key.uid, part: item.part)
                }) else { continue }
                self?.store(body, key: item.key)
                fetched += 1
            }
            if fetched > 0 {
                self?.log.info("prefetched bodies=\(fetched, privacy: .public)")
            }
        }
    }

    // MARK: - Compose

    /// Reply / Reply all / Forward the open message. Re-opening the same
    /// message in the same mode keeps its draft; switching mode re-seeds
    /// recipients, subject and threading but keeps the typed text.
    func startReply(_ mode: ReplyMode = .reply) {
        guard let message = openMessage else { return }
        if composeSourceKey != message.key {
            clearDraft()
            composeSourceKey = message.key
        }
        if composeMode != mode {
            seedCompose(mode, from: message)
        }
        sendError = nil
        didSend = false
        isComposeOpen = true
    }

    private func seedCompose(_ mode: ReplyMode, from message: EmailMessage) {
        // Leaving Forward takes its quoted block back out of the draft; the
        // user's own words above it stay.
        if let quote = composeQuote, draft.hasSuffix(quote) {
            draft = String(draft.dropLast(quote.count))
            composeQuote = nil
        }
        switch mode {
        case .reply:
            composeTo = message.replyTo ?? message.fromAddress
            composeCc = ""
            composeSubject = MailComposer.replySubject(message.subject)
            composeInReplyTo = message.messageID
            composeReferences = message.references
        case .replyAll:
            composeTo = message.replyTo ?? message.fromAddress
            composeCc = replyAllRecipients(for: message).joined(separator: ", ")
            composeSubject = MailComposer.replySubject(message.subject)
            composeInReplyTo = message.messageID
            composeReferences = message.references
        case .forward:
            composeTo = ""
            composeCc = ""
            composeSubject = MailComposer.forwardSubject(message.subject)
            composeInReplyTo = nil
            composeReferences = []
            let quote = MailComposer.forwardQuote(
                of: message,
                text: forwardText(of: message),
                headerLabel: L10n.t(.mailForwardedHeader)
            )
            draft = draft.trimmingCharacters(in: .whitespacesAndNewlines) + quote
            composeQuote = quote
        }
        composeMode = mode
    }

    /// The readable text of a message for quoting: the plain part, else
    /// the HTML flattened.
    private func forwardText(of message: EmailMessage) -> String {
        let current = messageInMemory(message.key) ?? message
        if let plain = current.bodyPlain, !plain.isEmpty { return plain }
        if let html = current.bodyHTML {
            return MIMEDecode.htmlToPlainText(html).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    /// Everyone on the message besides its sender and this account,
    /// first occurrence wins.
    func replyAllRecipients(for message: EmailMessage) -> [String] {
        var excluded = Set([message.fromAddress, message.replyTo ?? "", config?.email ?? ""].map { $0.lowercased() })
        var result: [String] = []
        for address in message.to + message.cc {
            let key = address.lowercased()
            guard !key.isEmpty, !excluded.contains(key) else { continue }
            excluded.insert(key)
            result.append(address)
        }
        return result
    }

    /// Blank message. An unsent new-mail draft survives closing the form;
    /// only leftovers of a reply are cleared.
    func startNewMail() {
        if composeSourceKey != nil {
            clearDraft()
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
        clearDraft()
        sendError = nil
    }

    var canSendCompose: Bool {
        !isSending
            && composeTo.trimmingCharacters(in: .whitespaces).contains("@")
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// "a@x.com, b@y.com" → ["a@x.com", "b@y.com"]
    private static func addressList(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.contains("@") }
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
            cc: Self.addressList(composeCc),
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
        let key = message.key
        // The badge counts INBOX; a message read in another folder is not
        // in it (or, on Gmail, the next poll settles it).
        if key.mailbox == "INBOX", messageInMemory(key)?.isUnread ?? message.isUnread {
            unreadCount = max(0, unreadCount - 1)
        }
        updateEverywhere(key) { $0.isUnread = false }
        Task {
            // Failure is fine: the next poll reconciles the flag.
            try? await session.run(in: key.mailbox) { try await $0.markSeen(uid: key.uid) }
        }
    }
}
