import Foundation

/// Whether Pocket is usable right now. See GLOSSARY.md for Trial, License
/// and Activation.
enum AccessState: Equatable, Sendable {
    /// Inside the Trial; `daysLeft` counts started days, so it runs 3, 2, 1.
    case trial(daysLeft: Int)
    case licensed
    case locked(LockReason)

    var isLocked: Bool {
        if case .locked = self { return true }
        return false
    }
}

enum LockReason: Equatable, Sendable {
    case trialEnded
    /// First launch without a connection: the Trial has not started yet.
    case needsConnectionToStartTrial
    /// The License could not be re-validated for longer than the grace period.
    case offlineTooLong
    /// The store answered that the License key is refunded, disabled or gone.
    case licenseInvalid
}

/// Why an Activation or deactivation did not go through.
enum AccessError: Error, Equatable, Sendable {
    case invalidKey
    case activationLimitReached
    /// The key is real but was sold for another product.
    case wrongProduct
    case noConnection
}

/// Everything licensing keeps on this Mac. Persisted as one Keychain item.
struct AccessRecord: Equatable, Codable, Sendable {
    var trialStart: Date?
    var licenseKey: String?
    var activationID: String?
    /// Last time the store confirmed the License key.
    var lastValidated: Date?
    /// The store's last answer was "invalid"; cleared by a valid answer.
    var licenseRevoked = false
    /// Latest time ever observed, so a clock moved back gains nothing.
    var latestSeen: Date?
    /// What the Mac's clock showed at that moment; time that passes on the
    /// clock afterwards still counts, even when the clock itself is wrong.
    var lastClockReading: Date?
}

/// Local persistence of the `AccessRecord`.
@MainActor
protocol AccessStore: AnyObject {
    func load() -> AccessRecord
    func save(_ record: AccessRecord)
}

/// Remembers when the Trial started on each Mac. Any thrown error means
/// "could not reach the server".
protocol TrialServer: Sendable {
    /// The Trial for `macID`, started by the server on first call.
    func trial(macID: String) async throws -> TrialStatus
}

struct TrialStatus: Equatable, Sendable {
    let start: Date
    /// The server's own clock — a time the Mac cannot set.
    let serverNow: Date
}

enum LicenseAPIError: Error, Equatable, Sendable {
    case invalidKey
    case activationLimitReached
    /// No answer, or one that cannot be trusted either way (timeouts, 5xx).
    case network
}

struct LicenseActivation: Equatable, Sendable {
    /// Identifies this Mac's Activation in later validate/deactivate calls.
    let activationID: String
    /// Product the key was sold for; the caller rejects foreign products.
    let productID: Int
}

enum LicenseValidity: Equatable, Sendable {
    case valid
    /// Refunded, disabled, expired, or the Activation no longer exists.
    case invalid
}

/// The store's license API. Every method throws `LicenseAPIError`.
protocol LicenseAPI: Sendable {
    func activate(licenseKey: String, activationName: String) async throws -> LicenseActivation
    func validate(licenseKey: String, activationID: String) async throws -> LicenseValidity
    /// Frees the Activation. Throws `.invalidKey` when the store no longer
    /// knows the key or the instance.
    func deactivate(licenseKey: String, activationID: String) async throws
}
