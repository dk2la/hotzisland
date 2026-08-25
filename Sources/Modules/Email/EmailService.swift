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

    @ObservationIgnored var onEditingChanged: ((Bool) -> Void)?

    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "email")
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let keychain = KeychainStore(service: EmailAccountConfig.keychainService)
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
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
            try keychain.setPassword(password, account: newConfig.email)
        } catch {
            lastError = "Keychain: \(error.localizedDescription)"
            return
        }
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
            try? keychain.deletePassword(account: config.email)
        }
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

    func refresh() {
        guard let config, refreshTask == nil else { return }
        guard let password = try? keychain.password(account: config.email), !password.isEmpty else {
            connection = .failed("No password in Keychain")
            return
        }
        connection = messages.isEmpty ? .connecting : connection
        refreshTask = Task { [weak self] in
            defer { self?.refreshTask = nil }
            let client = IMAPClient(host: config.imapHost, port: config.imapPort)
            do {
                try await client.connect()
                try await client.login(user: config.email, password: password)
                let exists = try await client.selectInbox()
                let unread = try await client.searchUnseenCount()
                let fetched = try await client.fetchHeaders(exists: exists, limit: Self.messageLimit)
                await client.logout()
                guard let self, !Task.isCancelled else { return }
                self.unreadCount = unread
                self.messages = fetched
                self.connection = .online
                self.lastRefresh = Date()
                self.lastError = nil
                self.log.info("refreshed exists=\(exists, privacy: .public) unread=\(unread, privacy: .public)")
            } catch {
                await client.logout()
                guard let self, !Task.isCancelled else { return }
                self.connection = .failed(error.localizedDescription)
                self.log.error("refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Message actions

    func open(_ message: EmailMessage) {
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
    }

    private func loadBody(for message: EmailMessage) {
        guard let config,
              let password = try? keychain.password(account: config.email) else { return }
        isLoadingBody = true
        Task { [weak self] in
            let client = IMAPClient(host: config.imapHost, port: config.imapPort)
            var body = ""
            do {
                try await client.connect()
                try await client.login(user: config.email, password: password)
                _ = try await client.selectInbox()
                body = try await client.fetchPlainBody(uid: message.uid, part: message.textPart)
                await client.logout()
            } catch {
                await client.logout()
                body = ""
            }
            guard let self else { return }
            self.isLoadingBody = false
            let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if var open = self.openMessage, open.uid == message.uid {
                open.bodyPlain = text
                self.openMessage = open
            }
            if let index = self.messages.firstIndex(where: { $0.uid == message.uid }) {
                self.messages[index].bodyPlain = text
            }
        }
    }

    /// Optimistic local flip, then the server call.
    func markRead(_ message: EmailMessage) {
        guard let config,
              let password = try? keychain.password(account: config.email) else { return }
        if let index = messages.firstIndex(where: { $0.uid == message.uid }), messages[index].isUnread {
            messages[index].isUnread = false
            unreadCount = max(0, unreadCount - 1)
        }
        if var open = openMessage, open.uid == message.uid {
            open.isUnread = false
            openMessage = open
        }
        Task {
            let client = IMAPClient(host: config.imapHost, port: config.imapPort)
            do {
                try await client.connect()
                try await client.login(user: config.email, password: password)
                _ = try await client.selectInbox()
                try await client.markSeen(uid: message.uid)
            } catch {
                // Reconciled by the next poll.
            }
            await client.logout()
        }
    }
}
