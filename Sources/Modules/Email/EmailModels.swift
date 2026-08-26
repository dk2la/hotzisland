import Foundation

/// Mail account configuration. Non-secret parts live in UserDefaults; the
/// password lives in the Keychain under the account's email address.
struct EmailAccountConfig: Codable, Equatable {
    var email: String
    var imapHost: String
    var imapPort: UInt16
    var smtpHost: String
    var smtpPort: UInt16
    var smtpUsesSTARTTLS: Bool
    var presetID: String

    static let defaultsKey = "email.account.v1"
    static let keychainService = "com.dk2la.hotzisland.email"
}

/// Provider presets — prefill hosts/ports and carry the auth hint.
enum EmailProvider: String, CaseIterable, Identifiable {
    case gmail
    case icloud
    case yandex
    case outlook
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gmail: "Gmail"
        case .icloud: "iCloud"
        case .yandex: "Yandex"
        case .outlook: "Outlook"
        case .custom: "Custom"
        }
    }

    /// (imapHost, imapPort, smtpHost, smtpPort, startTLS)
    var preset: (String, UInt16, String, UInt16, Bool)? {
        switch self {
        case .gmail: ("imap.gmail.com", 993, "smtp.gmail.com", 465, false)
        case .icloud: ("imap.mail.me.com", 993, "smtp.mail.me.com", 587, true)
        case .yandex: ("imap.yandex.com", 993, "smtp.yandex.com", 465, false)
        case .outlook: ("outlook.office365.com", 993, "smtp-mail.outlook.com", 587, true)
        case .custom: nil
        }
    }

    /// Personal Outlook killed password auth for IMAP — warn up front.
    var isPasswordAuthUnreliable: Bool { self == .outlook }
}

/// One inbox message. `bodyPlain` is filled lazily on open.
struct EmailMessage: Identifiable, Equatable, Sendable {
    let uid: UInt32
    var subject: String
    var fromName: String
    var fromAddress: String
    var date: Date
    var isUnread: Bool
    var messageID: String?
    var references: [String]
    var bodyPlain: String?
    /// Where the readable part lives and how it is encoded.
    var textPart: TextPartInfo?

    var id: UInt32 { uid }

    struct TextPartInfo: Equatable, Sendable {
        var section: String
        var encoding: String
        var charset: String
        /// text/html parts are flattened to text after decoding.
        var isHTML: Bool = false
    }
}

/// What one body fetch brings back: the readable text plus the threading
/// chain, which ENVELOPE does not carry.
struct MessageBody: Sendable {
    var text: String
    var references: [String]
}

/// A reply ready for the wire.
struct OutgoingMail: Sendable {
    var from: String
    var to: String
    var subject: String
    var body: String
    var inReplyTo: String?
    var references: [String]
}

enum MailConnectionState: Equatable {
    case offline
    case connecting
    case online
    case failed(String)
}

enum MailError: Error, LocalizedError {
    case timeout
    case connectionClosed
    case badResponse(String)
    case authFailed(String)
    case tls(String)

    var errorDescription: String? {
        switch self {
        case .timeout: "Connection timed out"
        case .connectionClosed: "Connection closed"
        case .badResponse(let s): s
        case .authFailed(let s): s
        case .tls(let s): s
        }
    }
}
