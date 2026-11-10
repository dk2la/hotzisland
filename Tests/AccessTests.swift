import XCTest

/// Licensing rules, driven through `Access` with fakes for the clock, the
/// local store, the Trial server and the license API.
@MainActor
final class AccessTests: XCTestCase {
    private static let pocketProduct = 1001
    private static let macID = "mac-a"

    /// One Mac and the world around it. `launch()` is an app start: a new
    /// `Access` over the same store, refreshed once.
    @MainActor
    private final class World {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock: FakeClock
        var store = FakeAccessStore()
        let trialServer = FakeTrialServer()
        let api = FakeLicenseAPI()

        init() {
            clock = FakeClock(start)
            trialServer.serverDate = start
        }

        func launch() async -> Access {
            let clock = clock
            let access = Access(
                store: store,
                trialServer: trialServer,
                licenseAPI: api,
                macID: AccessTests.macID,
                productID: AccessTests.pocketProduct,
                now: { clock.now }
            )
            await access.refresh()
            return access
        }

        /// Deleting Pocket's data (or reinstalling) empties the local store.
        func wipeLocalData() {
            store = FakeAccessStore()
        }

        /// Moves both the Mac's clock and the server's.
        func advance(days: Double) {
            clock.advance(days: days)
            trialServer.serverDate = clock.now
        }

        func sellKey(activationID: String = "inst-1", productID: Int = AccessTests.pocketProduct) {
            api.activateResult = .success(LicenseActivation(activationID: activationID, productID: productID))
        }

        /// A launched, licensed Pocket.
        func launchLicensed() async throws -> Access {
            let access = await launch()
            sellKey()
            try await access.activate(licenseKey: "KEY-1")
            return access
        }
    }

    private func assertThrows(
        _ expected: AccessError,
        _ body: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AccessError, expected, file: file, line: line)
        }
    }

    // MARK: - Trial

    func testFirstLaunchOnlineStartsThreeDayTrial() async {
        let world = World()
        let access = await world.launch()
        XCTAssertEqual(access.state, .trial(daysLeft: 3))
    }

    func testTrialDaysCountDown() async {
        let world = World()
        let access = await world.launch()
        world.advance(days: 1.5)
        await access.refresh()
        XCTAssertEqual(access.state, .trial(daysLeft: 2))
        world.advance(days: 1)
        await access.refresh()
        XCTAssertEqual(access.state, .trial(daysLeft: 1))
    }

    func testTrialEndsAfterThreeDays() async {
        let world = World()
        let access = await world.launch()
        world.advance(days: 3)
        await access.refresh()
        XCTAssertEqual(access.state, .locked(.trialEnded))
    }

    func testFirstLaunchOfflineNeedsConnection() async {
        let world = World()
        world.trialServer.isOnline = false
        let access = await world.launch()
        XCTAssertEqual(access.state, .locked(.needsConnectionToStartTrial))
    }

    func testTrialStartsOnceConnectionAppears() async {
        let world = World()
        world.trialServer.isOnline = false
        let access = await world.launch()
        world.trialServer.isOnline = true
        await access.refresh()
        XCTAssertEqual(access.state, .trial(daysLeft: 3))
    }

    func testStartedTrialWorksOffline() async {
        let world = World()
        _ = await world.launch()
        world.advance(days: 1.5)
        world.trialServer.isOnline = false
        let relaunched = await world.launch()
        XCTAssertEqual(relaunched.state, .trial(daysLeft: 2))
    }

    func testWipingLocalDataDoesNotRestartTrial() async {
        let world = World()
        _ = await world.launch()
        world.advance(days: 2.5)
        world.wipeLocalData()
        let reinstalled = await world.launch()
        XCTAssertEqual(reinstalled.state, .trial(daysLeft: 1))
    }

    func testServerDateWinsOverLocalCopy() async {
        let world = World()
        _ = await world.launch()
        world.advance(days: 2.5)
        // A doctored local copy claims the Trial started just now.
        world.store.record.trialStart = world.clock.now
        let relaunched = await world.launch()
        XCTAssertEqual(relaunched.state, .trial(daysLeft: 1))
    }

    func testTrialIsRegisteredUnderTheMacID() async {
        let world = World()
        _ = await world.launch()
        XCTAssertEqual(world.trialServer.knownMacIDs, ["mac-a"])
    }

    // MARK: - Activation

    func testActivationDuringTrialLicenses() async throws {
        let world = World()
        let access = await world.launch()
        world.sellKey()
        try await access.activate(licenseKey: "KEY-1")
        XCTAssertEqual(access.state, .licensed)
        XCTAssertEqual(access.licenseKey, "KEY-1")
        XCTAssertEqual(world.api.activationNames, ["mac-a"])
    }

    func testActivationAfterTrialEndedUnlocks() async throws {
        let world = World()
        let access = await world.launch()
        world.advance(days: 10)
        await access.refresh()
        XCTAssertEqual(access.state, .locked(.trialEnded))
        world.sellKey()
        try await access.activate(licenseKey: "KEY-1")
        XCTAssertEqual(access.state, .licensed)
    }

    func testLicensePersistsAcrossLaunches() async throws {
        let world = World()
        _ = try await world.launchLicensed()
        world.advance(days: 5)
        let relaunched = await world.launch()
        XCTAssertEqual(relaunched.state, .licensed)
        XCTAssertEqual(relaunched.licenseKey, "KEY-1")
    }

    func testWrongKeyIsRejectedAndStateUnchanged() async {
        let world = World()
        let access = await world.launch()
        world.api.activateResult = .failure(.invalidKey)
        await assertThrows(.invalidKey) { try await access.activate(licenseKey: "TYPO") }
        XCTAssertEqual(access.state, .trial(daysLeft: 3))
    }

    func testActivationLimitIsReportedAndStateUnchanged() async {
        let world = World()
        let access = await world.launch()
        world.api.activateResult = .failure(.activationLimitReached)
        await assertThrows(.activationLimitReached) { try await access.activate(licenseKey: "KEY-1") }
        XCTAssertEqual(access.state, .trial(daysLeft: 3))
    }

    func testActivationWithoutConnectionIsReported() async {
        let world = World()
        let access = await world.launch()
        world.api.activateResult = .failure(.network)
        await assertThrows(.noConnection) { try await access.activate(licenseKey: "KEY-1") }
        XCTAssertEqual(access.state, .trial(daysLeft: 3))
    }

    func testKeyForAnotherProductIsRejectedAndItsActivationFreed() async {
        let world = World()
        let access = await world.launch()
        world.sellKey(activationID: "foreign", productID: 2002)
        await assertThrows(.wrongProduct) { try await access.activate(licenseKey: "OTHER-APP") }
        XCTAssertEqual(access.state, .trial(daysLeft: 3))
        XCTAssertEqual(world.api.freedActivations, ["foreign"])
        let relaunched = await world.launch()
        XCTAssertEqual(relaunched.state, .trial(daysLeft: 3))
    }

    // MARK: - Daily re-validation

    func testValidationRunsAtMostOnceADay() async throws {
        let world = World()
        let access = try await world.launchLicensed()
        world.advance(days: 0.5)
        await access.refresh()
        XCTAssertEqual(world.api.validateCount, 0)
        world.advance(days: 0.6)
        await access.refresh()
        await access.refresh()
        XCTAssertEqual(world.api.validateCount, 1)
        XCTAssertEqual(access.state, .licensed)
    }

    func testOverdueValidationRunsAtLaunch() async throws {
        let world = World()
        _ = try await world.launchLicensed()
        world.advance(days: 2)
        _ = await world.launch()
        XCTAssertEqual(world.api.validateCount, 1)
    }

    func testRevokedLicenseLocksImmediately() async throws {
        let world = World()
        let access = try await world.launchLicensed()
        world.advance(days: 1)
        world.api.validateResult = .success(.invalid)
        await access.refresh()
        XCTAssertEqual(access.state, .locked(.licenseInvalid))
    }

    func testRevokedLicenseStaysLockedOffline() async throws {
        let world = World()
        let access = try await world.launchLicensed()
        world.advance(days: 1)
        world.api.validateResult = .success(.invalid)
        await access.refresh()
        world.api.validateResult = .failure(.network)
        let relaunched = await world.launch()
        XCTAssertEqual(relaunched.state, .locked(.licenseInvalid))
    }

    func testReinstatedLicenseUnlocks() async throws {
        let world = World()
        let access = try await world.launchLicensed()
        world.advance(days: 1)
        world.api.validateResult = .success(.invalid)
        await access.refresh()
        world.api.validateResult = .success(.valid)
        await access.refresh()
        XCTAssertEqual(access.state, .licensed)
    }

    // MARK: - Offline grace

    func testOfflineWithinGraceStaysLicensed() async throws {
        let world = World()
        let access = try await world.launchLicensed()
        world.api.validateResult = .failure(.network)
        world.advance(days: 6.9)
        await access.refresh()
        XCTAssertEqual(access.state, .licensed)
    }

    func testOfflineBeyondGraceLocks() async throws {
        let world = World()
        let access = try await world.launchLicensed()
        world.api.validateResult = .failure(.network)
        world.advance(days: 7.1)
        await access.refresh()
        XCTAssertEqual(access.state, .locked(.offlineTooLong))
    }

    func testReconnectingAfterGraceUnlocks() async throws {
        let world = World()
        let access = try await world.launchLicensed()
        world.api.validateResult = .failure(.network)
        world.advance(days: 8)
        await access.refresh()
        world.api.validateResult = .success(.valid)
        await access.refresh()
        XCTAssertEqual(access.state, .licensed)
    }

    func testGraceCountsFromLastSuccessfulCheck() async throws {
        let world = World()
        let access = try await world.launchLicensed()
        world.advance(days: 5)
        await access.refresh() // succeeds
        world.api.validateResult = .failure(.network)
        world.advance(days: 6)
        await access.refresh()
        XCTAssertEqual(access.state, .licensed)
    }

    // MARK: - Deactivation

    func testDeactivationReturnsToTrialWhileDaysRemain() async throws {
        let world = World()
        let access = try await world.launchLicensed()
        world.advance(days: 1.5)
        try await access.deactivate()
        XCTAssertEqual(access.state, .trial(daysLeft: 2))
        XCTAssertNil(access.licenseKey)
        XCTAssertEqual(world.api.freedActivations, ["inst-1"])
        let relaunched = await world.launch()
        XCTAssertEqual(relaunched.state, .trial(daysLeft: 2))
    }

    func testDeactivationAfterTrialLocks() async throws {
        let world = World()
        let access = try await world.launchLicensed()
        world.advance(days: 30)
        try await access.deactivate()
        XCTAssertEqual(access.state, .locked(.trialEnded))
    }

    func testFailedDeactivationChangesNothing() async throws {
        let world = World()
        let access = try await world.launchLicensed()
        world.api.deactivateResult = .failure(.network)
        await assertThrows(.noConnection) { try await access.deactivate() }
        XCTAssertEqual(access.state, .licensed)
        let relaunched = await world.launch()
        XCTAssertEqual(relaunched.state, .licensed)
        XCTAssertEqual(relaunched.licenseKey, "KEY-1")
    }

    // MARK: - Clock tampering

    func testClockMovedBackDoesNotAddTrialDays() async {
        let world = World()
        let access = await world.launch()
        world.advance(days: 2.5)
        await access.refresh()
        XCTAssertEqual(access.state, .trial(daysLeft: 1))
        world.clock.now = world.start
        await access.refresh()
        XCTAssertEqual(access.state, .trial(daysLeft: 1))
        let relaunched = await world.launch()
        XCTAssertEqual(relaunched.state, .trial(daysLeft: 1))
    }

    func testClockMovedBackDoesNotReviveEndedTrial() async {
        let world = World()
        let access = await world.launch()
        world.advance(days: 4)
        await access.refresh()
        world.clock.now = world.start
        world.trialServer.isOnline = false
        let relaunched = await world.launch()
        XCTAssertEqual(relaunched.state, .locked(.trialEnded))
    }

    func testClockMovedBackDoesNotExtendOfflineGrace() async throws {
        let world = World()
        let access = try await world.launchLicensed()
        world.api.validateResult = .failure(.network)
        world.advance(days: 8)
        await access.refresh()
        XCTAssertEqual(access.state, .locked(.offlineTooLong))
        world.clock.now = world.start.addingTimeInterval(86_400)
        await access.refresh()
        XCTAssertEqual(access.state, .locked(.offlineTooLong))
        let relaunched = await world.launch()
        XCTAssertEqual(relaunched.state, .locked(.offlineTooLong))
    }

    func testClockBehindTheServerDoesNotLengthenTrial() async {
        let world = World()
        // The Mac's clock is a week behind the server's.
        world.clock.now = world.start.addingTimeInterval(-7 * 86_400)
        let access = await world.launch()
        XCTAssertEqual(access.state, .trial(daysLeft: 3))
    }

    func testTrialRunsOutOnAMacWhoseClockIsBehind() async {
        let world = World()
        world.clock.now = world.start.addingTimeInterval(-30 * 86_400)
        let access = await world.launch()
        // Three real days pass; the Mac's clock is still a month behind.
        world.clock.advance(days: 3)
        world.trialServer.isOnline = false
        await access.refresh()
        XCTAssertEqual(access.state, .locked(.trialEnded))
    }

    func testClockBehindAndWipedDataDoesNotRestartTrial() async {
        let world = World()
        _ = await world.launch()
        world.advance(days: 5)
        world.wipeLocalData()
        world.clock.now = world.start
        let reinstalled = await world.launch()
        XCTAssertEqual(reinstalled.state, .locked(.trialEnded))
    }

    func testClockSetForwardOnceDoesNotStopRevalidation() async throws {
        let world = World()
        let access = try await world.launchLicensed()
        world.clock.advance(days: 1000)
        await access.refresh()
        XCTAssertEqual(world.api.validateCount, 1)
        // Back to the real date; the License is refunded a day later.
        world.clock.now = world.start
        await access.refresh()
        world.clock.advance(days: 1.1)
        world.api.validateResult = .success(.invalid)
        await access.refresh()
        XCTAssertEqual(access.state, .locked(.licenseInvalid))
    }

    // MARK: - Mac ID

    func testMacIDIsHashedBeforeLeavingTheMac() {
        let hardwareID = "564D8A3B-1C2D-4E5F-9A0B-112233445566"
        let hashed = MacID.hashed(hardwareID: hardwareID)
        XCTAssertEqual(hashed.count, 64)
        XCTAssertTrue(hashed.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        XCTAssertFalse(hashed.localizedCaseInsensitiveContains("564D8A3B"))
        XCTAssertEqual(hashed, MacID.hashed(hardwareID: hardwareID))
        XCTAssertNotEqual(hashed, MacID.hashed(hardwareID: "another-mac"))
    }
}
