import Foundation
import OSLog

/// The `AccessRecord` as one JSON item in the Keychain — one item, so at
/// most one access prompt. Nothing licensing-related lives in UserDefaults.
@MainActor
final class KeychainAccessStore: AccessStore {
    #if DEBUG
    // A debug build testing the flow must not disturb the real app's record.
    private let keychain = KeychainStore(service: "com.dk2la.pocket.licensing.debug")
    #else
    private let keychain = KeychainStore(service: "com.dk2la.pocket.licensing")
    #endif
    private let account = "access"
    private let log = Logger(subsystem: "com.dk2la.pocket", category: "licensing")

    func load() -> AccessRecord {
        guard let json = try? keychain.password(account: account),
              let record = try? JSONDecoder().decode(AccessRecord.self, from: Data(json.utf8)) else {
            return AccessRecord()
        }
        return record
    }

    func save(_ record: AccessRecord) {
        do {
            let json = String(data: try JSONEncoder().encode(record), encoding: .utf8) ?? ""
            try keychain.setPassword(json, account: account)
        } catch {
            log.error("saving the access record failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Keeps the record for this launch only. Used when licensing is skipped,
/// so a debug build never touches the Keychain item of the real app.
@MainActor
final class MemoryAccessStore: AccessStore {
    private var record = AccessRecord()

    func load() -> AccessRecord { record }
    func save(_ record: AccessRecord) { self.record = record }
}

extension Access {
    /// The app's instance, wired to the real servers.
    static func live(enforced: Bool) -> Access {
        Access(
            store: enforced ? KeychainAccessStore() : MemoryAccessStore(),
            trialServer: TrialServerClient(baseURL: LicensingConfig.trialServerURL),
            licenseAPI: LemonSqueezyLicenseAPI(),
            macID: MacID.current,
            productID: LicensingConfig.productID
        )
    }
}
