import Foundation
import OSLog

/// Minimal SMTP submission client: greeting → EHLO → (STARTTLS → EHLO) →
/// AUTH → MAIL FROM → RCPT TO → DATA → QUIT. One session per send, like the
/// IMAP side.
actor SMTPClient {
    private let transport: StreamTransport
    private let usesSTARTTLS: Bool
    private var capabilities = ""
    private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "email")

    /// EHLO needs a name; we have no resolvable hostname, and RFC 5321 allows
    /// an address literal in that case.
    private static let clientName = "[127.0.0.1]"

    init(host: String, port: UInt16, usesSTARTTLS: Bool) {
        transport = StreamTransport(host: host, port: port)
        self.usesSTARTTLS = usesSTARTTLS
    }

    // MARK: - Session

    func connect() async throws {
        try await transport.connect(useTLS: !usesSTARTTLS)
        _ = try await readReply(expecting: [220])
        capabilities = try await command("EHLO \(Self.clientName)", expecting: [250])
        if usesSTARTTLS {
            _ = try await command("STARTTLS", expecting: [220])
            try await transport.startTLS()
            capabilities = try await command("EHLO \(Self.clientName)", expecting: [250])
        }
        log.info("smtp ready starttls=\(self.usesSTARTTLS, privacy: .public)")
    }

    func login(user: String, password: String) async throws {
        do {
            if capabilities.uppercased().contains("PLAIN") {
                var token = Data([0])
                token.append(contentsOf: user.utf8)
                token.append(0)
                token.append(contentsOf: password.utf8)
                _ = try await command("AUTH PLAIN \(token.base64EncodedString())", expecting: [235], redacted: true)
            } else {
                _ = try await command("AUTH LOGIN", expecting: [334])
                _ = try await command(Data(user.utf8).base64EncodedString(), expecting: [334], redacted: true)
                _ = try await command(Data(password.utf8).base64EncodedString(), expecting: [235], redacted: true)
            }
        } catch let MailError.badResponse(message) {
            throw MailError.authFailed(message)
        }
    }

    func send(_ mail: OutgoingMail) async throws {
        _ = try await command("MAIL FROM:<\(mail.from)>", expecting: [250])
        _ = try await command("RCPT TO:<\(mail.to)>", expecting: [250, 251])
        _ = try await command("DATA", expecting: [354])
        // The composed message ends with CRLF, so "." lands on its own line.
        try await transport.send(Data(MailComposer.rfc5322(mail).utf8))
        _ = try await command(".", expecting: [250])
        log.info("smtp sent bytes=\(mail.body.utf8.count, privacy: .public)")
    }

    func quit() async {
        _ = try? await command("QUIT", expecting: [221])
        await transport.close()
    }

    // MARK: - Wire protocol

    @discardableResult
    private func command(_ text: String, expecting codes: Set<Int>, redacted: Bool = false) async throws -> String {
        try await transport.send(Data("\(text)\r\n".utf8))
        if !redacted {
            log.debug("smtp > \(text, privacy: .public)")
        }
        return try await readReply(expecting: codes)
    }

    /// Reads one reply, following "250-" continuation lines to the final one.
    private func readReply(expecting codes: Set<Int>) async throws -> String {
        var full = ""
        while true {
            let line = try await transport.readLine()
            let text = String(decoding: line, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            full += full.isEmpty ? text : "\n\(text)"
            guard let code = Int(text.prefix(3)) else { throw MailError.badResponse(text) }
            // A dash right after the code means more lines follow.
            if text.count > 3, Array(text)[3] == "-" { continue }
            guard codes.contains(code) else { throw MailError.badResponse(full) }
            return full
        }
    }
}
