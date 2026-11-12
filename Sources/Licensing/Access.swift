import Foundation
import Observation

/// Decides whether Pocket is usable: Trial, License or locked. The one
/// place licensing rules live — the UI only reads `state` and calls the
/// actions. Time, persistence and both servers are injected, so every rule
/// is testable with fakes.
@MainActor
@Observable
final class Access {
    static let trialLength: TimeInterval = 3 * day
    /// The License key is re-validated once this much time has passed.
    static let validationInterval: TimeInterval = day
    /// How long Pocket keeps working without a successful validation.
    static let offlineGrace: TimeInterval = 7 * day
    private static let day: TimeInterval = 86_400

    private(set) var state: AccessState
    /// A refresh is talking to a server; the lock screen shows progress
    /// instead of a verdict that may be about to change.
    private(set) var isRefreshing = false
    /// The activated License key, for display.
    var licenseKey: String? { record.licenseKey }

    private var record: AccessRecord
    @ObservationIgnored private var savedRecord: AccessRecord
    @ObservationIgnored private let store: any AccessStore
    @ObservationIgnored private let trialServer: any TrialServer
    @ObservationIgnored private let licenseAPI: any LicenseAPI
    @ObservationIgnored private let macID: String
    @ObservationIgnored private let productID: Int
    @ObservationIgnored private let clock: @MainActor () -> Date
    /// The server confirmed the Trial start during this launch; no need to
    /// ask again.
    @ObservationIgnored private var trialConfirmed = false
    /// Last queued action — actions run one at a time, in call order.
    @ObservationIgnored private var tail: Task<Void, Never>?

    /// - Parameters:
    ///   - macID: hashed Mac ID; names this Mac to both servers.
    ///   - productID: the store's product a License key must belong to.
    init(
        store: any AccessStore,
        trialServer: any TrialServer,
        licenseAPI: any LicenseAPI,
        macID: String,
        productID: Int,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.store = store
        self.trialServer = trialServer
        self.licenseAPI = licenseAPI
        self.macID = macID
        self.productID = productID
        clock = now
        let loaded = store.load()
        record = loaded
        savedRecord = loaded
        // Until the first refresh the local copy is all there is.
        state = Self.evaluate(loaded, at: Self.effectiveNow(loaded, clock: now()))
    }

    // MARK: - Actions

    /// Brings `state` up to date: starts or confirms the Trial, or
    /// re-validates the License key when a validation is due. Call at
    /// launch and periodically; it is cheap when nothing is due.
    func refresh() async {
        try? await serialized { [self] in
            // Raised only when a server is about to be asked, so the lock
            // screen does not blink "checking" on refreshes with nothing due.
            isRefreshing = needsServer
            defer { isRefreshing = false }
            if let key = record.licenseKey, let activationID = record.activationID {
                await revalidateIfDue(key: key, activationID: activationID)
            } else {
                await confirmTrialStart()
            }
            settle()
        }
    }

    /// Activates `licenseKey` on this Mac. Throws `AccessError`; on failure
    /// the state is unchanged.
    func activate(licenseKey: String) async throws {
        try await serialized { [self] in
            let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw AccessError.invalidKey }
            let activation: LicenseActivation
            do {
                activation = try await licenseAPI.activate(licenseKey: key, activationName: macID)
            } catch {
                throw Self.accessError(error)
            }
            guard activation.productID == productID else {
                // Do not leave a foreign key's Activation used up.
                try? await licenseAPI.deactivate(licenseKey: key, activationID: activation.activationID)
                throw AccessError.wrongProduct
            }
            // Replacing a License (e.g. a revoked one): free the old Activation.
            if let oldKey = record.licenseKey, let oldActivation = record.activationID {
                try? await licenseAPI.deactivate(licenseKey: oldKey, activationID: oldActivation)
            }
            record.licenseKey = key
            record.activationID = activation.activationID
            record.lastValidated = observeNow()
            record.licenseRevoked = false
            settle()
        }
    }

    /// Frees this Mac's Activation and forgets the License key; Pocket goes
    /// back to the Trial, or locks if it is over. Throws
    /// `AccessError.noConnection` when the store is unreachable — nothing
    /// changes then.
    func deactivate() async throws {
        try await serialized { [self] in
            guard let key = record.licenseKey, let activationID = record.activationID else { return }
            do {
                try await licenseAPI.deactivate(licenseKey: key, activationID: activationID)
            } catch LicenseAPIError.invalidKey {
                // The store no longer knows this Activation: nothing to free.
            } catch {
                throw AccessError.noConnection
            }
            record.licenseKey = nil
            record.activationID = nil
            record.lastValidated = nil
            record.licenseRevoked = false
            await confirmTrialStart()
            settle()
        }
    }

    // MARK: - Rules

    /// A refresh right now would talk to a server.
    private var needsServer: Bool {
        record.licenseKey == nil ? !trialConfirmed : validationDue
    }

    /// A revoked License is re-checked every time, in case it is reinstated.
    private var validationDue: Bool {
        if record.licenseRevoked { return true }
        let now = observeNow()
        return record.lastValidated.map { now.timeIntervalSince($0) >= Self.validationInterval } ?? true
    }

    private func revalidateIfDue(key: String, activationID: String) async {
        guard validationDue else { return }
        do {
            switch try await licenseAPI.validate(licenseKey: key, activationID: activationID) {
            case .valid:
                record.lastValidated = observeNow()
                record.licenseRevoked = false
            case .invalid:
                record.licenseRevoked = true
            }
        } catch {
            // Unreachable store: the offline grace period decides.
        }
    }

    /// The server's date wins over the local copy, so wiping local data
    /// does not restart the Trial. Offline, the local copy stands.
    private func confirmTrialStart() async {
        guard !trialConfirmed else { return }
        guard let trial = try? await trialServer.trial(macID: macID) else { return }
        record.trialStart = trial.start
        // A Mac whose clock is behind the server's gains nothing from it.
        record.latestSeen = max(observeNow(), trial.serverNow)
        trialConfirmed = true
    }

    private func settle() {
        state = Self.evaluate(record, at: observeNow())
        if record != savedRecord {
            store.save(record)
            savedRecord = record
        }
    }

    /// The current time, never earlier than any time seen before.
    private func observeNow() -> Date {
        let reading = clock()
        let now = Self.effectiveNow(record, clock: reading)
        record.latestSeen = now
        record.lastClockReading = reading
        return now
    }

    /// The clock, unless it is behind what was already seen. Then time
    /// continues from the latest seen moment at the clock's pace, so a
    /// clock moved back (or forward once, then back) neither stops nor
    /// rewinds it.
    private static func effectiveNow(_ record: AccessRecord, clock: Date) -> Date {
        // The Trial start is a server time: the clock cannot be before it.
        var floor = max(record.latestSeen ?? .distantPast, record.trialStart ?? .distantPast)
        if let seen = record.latestSeen, let last = record.lastClockReading, clock > last {
            floor = max(floor, seen + clock.timeIntervalSince(last))
        }
        return max(clock, floor)
    }

    private static func evaluate(_ record: AccessRecord, at now: Date) -> AccessState {
        if record.licenseKey != nil, record.activationID != nil {
            if record.licenseRevoked { return .locked(.licenseInvalid) }
            guard let last = record.lastValidated, now.timeIntervalSince(last) <= offlineGrace else {
                return .locked(.offlineTooLong)
            }
            return .licensed
        }
        guard let start = record.trialStart else { return .locked(.needsConnectionToStartTrial) }
        let remaining = trialLength - now.timeIntervalSince(start)
        guard remaining > 0 else { return .locked(.trialEnded) }
        return .trial(daysLeft: Int((remaining / day).rounded(.up)))
    }

    private static func accessError(_ error: Error) -> AccessError {
        switch error as? LicenseAPIError {
        case .invalidKey: .invalidKey
        case .activationLimitReached: .activationLimitReached
        case .network, nil: .noConnection
        }
    }

    /// Runs `operation` after every action queued before it has finished.
    private func serialized(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            try await operation()
        }
        tail = Task { @MainActor in _ = try? await task.value }
        try await task.value
    }
}
