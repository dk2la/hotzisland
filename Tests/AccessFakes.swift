import Foundation

/// In-memory stand-in for the Keychain record. One instance shared between
/// `Access` instances plays the role of the same Mac across launches.
@MainActor
final class FakeAccessStore: AccessStore {
    var record = AccessRecord()

    func load() -> AccessRecord { record }
    func save(_ record: AccessRecord) { self.record = record }
}

/// Settable time source.
@MainActor
final class FakeClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }

    func advance(days: Double) {
        now += days * 86_400
    }
}

/// Trial server that remembers one start date per Mac ID, like the real
/// Worker. `isOnline = false` makes every call fail.
final class FakeTrialServer: TrialServer, @unchecked Sendable {
    struct Offline: Error {}

    private let lock = NSLock()
    private var starts: [String: Date] = [:]
    private var online = true
    private var today = Date(timeIntervalSince1970: 0)

    var isOnline: Bool {
        get { lock.withLock { online } }
        set { lock.withLock { online = newValue } }
    }

    /// The server's own clock.
    var serverDate: Date {
        get { lock.withLock { today } }
        set { lock.withLock { today = newValue } }
    }

    /// Mac IDs the server has a Trial for.
    var knownMacIDs: [String] {
        lock.withLock { Array(starts.keys) }
    }

    func trial(macID: String) async throws -> TrialStatus {
        try lock.withLock {
            guard online else { throw Offline() }
            let start = starts[macID] ?? today
            starts[macID] = start
            return TrialStatus(start: start, serverNow: today)
        }
    }
}

/// Scripted license API: each call answers with the configured result and
/// is recorded.
final class FakeLicenseAPI: LicenseAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var activation: Result<LicenseActivation, LicenseAPIError> = .failure(.network)
    private var validity: Result<LicenseValidity, LicenseAPIError> = .success(.valid)
    private var deactivation: Result<Void, LicenseAPIError> = .success(())
    private var validations = 0
    private var freed: [String] = []
    private var names: [String] = []

    var activateResult: Result<LicenseActivation, LicenseAPIError> {
        get { lock.withLock { activation } }
        set { lock.withLock { activation = newValue } }
    }

    var validateResult: Result<LicenseValidity, LicenseAPIError> {
        get { lock.withLock { validity } }
        set { lock.withLock { validity = newValue } }
    }

    var deactivateResult: Result<Void, LicenseAPIError> {
        get { lock.withLock { deactivation } }
        set { lock.withLock { deactivation = newValue } }
    }

    /// How many validations reached the store.
    var validateCount: Int { lock.withLock { validations } }
    /// Instance IDs whose Activation was freed.
    var freedActivations: [String] { lock.withLock { freed } }
    /// Instance names sent with activations.
    var activationNames: [String] { lock.withLock { names } }

    func activate(licenseKey: String, activationName: String) async throws -> LicenseActivation {
        try lock.withLock {
            names.append(activationName)
            return try activation.get()
        }
    }

    func validate(licenseKey: String, activationID: String) async throws -> LicenseValidity {
        try lock.withLock {
            validations += 1
            return try validity.get()
        }
    }

    func deactivate(licenseKey: String, activationID: String) async throws {
        try lock.withLock {
            try deactivation.get()
            freed.append(activationID)
        }
    }
}
