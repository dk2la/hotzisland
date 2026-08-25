import Foundation
import OSLog
import Security

/// Minimal generic-password Keychain wrapper. Uses the legacy file keychain
/// deliberately: with ad-hoc signing the app has no application-identifier
/// entitlement, so the data-protection keychain would fail with
/// errSecMissingEntitlement.
///
/// Dev note: `CODE_SIGN_IDENTITY: "-"` produces a new code signature every
/// rebuild, so macOS re-prompts for keychain access after each build even
/// after "Always Allow". For a quieter dev loop, create a stable self-signed
/// signing certificate locally and point CODE_SIGN_IDENTITY at it (do not
/// commit that change).
struct KeychainStore {
    let service: String

    enum KeychainError: Error {
        case status(OSStatus)
    }

    private static let log = Logger(subsystem: "com.dk2la.hotzisland", category: "keychain")

    /// Stores or replaces the secret for `account`. The value itself is
    /// never logged.
    func setPassword(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            Self.log.error("set failed status=\(status, privacy: .public) service=\(self.service, privacy: .public)")
            throw KeychainError.status(status)
        }
    }

    func password(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            Self.log.error("get failed status=\(status, privacy: .public) service=\(self.service, privacy: .public)")
            throw KeychainError.status(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func deletePassword(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Self.log.error("delete failed status=\(status, privacy: .public) service=\(self.service, privacy: .public)")
            throw KeychainError.status(status)
        }
    }
}
