import Foundation
import OSLog
import Security

/// Minimal generic-password Keychain wrapper. Uses the legacy file keychain
/// deliberately: without an application-identifier entitlement (which needs
/// a provisioning profile) the data-protection keychain would fail with
/// errSecMissingEntitlement.
///
/// Access-prompt model of the legacy keychain: the app that CREATES an item
/// reads it silently forever; any app with a different code signature hits
/// the password dialog. Hence two rules embodied here:
/// - Builds must be signed with a stable identity (Support/Signing.xcconfig),
///   or every rebuild is "a different app".
/// - Saving replaces the item (delete + add) rather than updating it, so the
///   item is always owned by the signature of the running build.
struct KeychainStore {
    let service: String

    enum KeychainError: Error {
        case status(OSStatus)
    }

    private static let log = Logger(subsystem: "com.dk2la.hotzisland", category: "keychain")

    /// Stores or replaces the secret for `account`. The value itself is
    /// never logged. Replacement is delete + add, NOT SecItemUpdate: update
    /// keeps the existing item's ACL, which may still point at a build with
    /// a different signature — the source of endless access prompts. A fresh
    /// add makes the running build the item's owner, which reads silently.
    func setPassword(_ value: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            Self.log.error("replace-delete failed status=\(deleteStatus, privacy: .public) service=\(self.service, privacy: .public)")
            throw KeychainError.status(deleteStatus)
        }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(add as CFDictionary, nil)
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
