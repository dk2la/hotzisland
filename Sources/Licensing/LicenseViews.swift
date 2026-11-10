import AppKit
import SwiftUI

/// Words for the licensing states, shared by the lock screen and Settings.
@MainActor
enum LicenseText {
    static func title(_ reason: LockReason) -> String {
        switch reason {
        case .trialEnded: L10n.t(.licTrialEndedTitle)
        case .needsConnectionToStartTrial: L10n.t(.licNeedsConnectionTitle)
        case .offlineTooLong: L10n.t(.licOfflineTitle)
        case .licenseInvalid: L10n.t(.licInvalidTitle)
        }
    }

    static func detail(_ reason: LockReason) -> String {
        switch reason {
        case .trialEnded: L10n.t(.licTrialEndedSub)
        case .needsConnectionToStartTrial: L10n.t(.licNeedsConnectionSub)
        case .offlineTooLong: L10n.t(.licOfflineSub)
        case .licenseInvalid: L10n.t(.licInvalidSub)
        }
    }

    static func message(_ error: AccessError) -> String {
        switch error {
        case .invalidKey: L10n.t(.licErrInvalidKey)
        case .activationLimitReached: L10n.t(.licErrLimit)
        case .wrongProduct: L10n.t(.licErrWrongProduct)
        case .noConnection: L10n.t(.licErrNoConnection)
        }
    }

    static func status(_ state: AccessState) -> String {
        switch state {
        case .trial(let daysLeft): "\(L10n.t(.licTrial)) · \(L10n.f(.licTrialDaysLeft, daysLeft))"
        case .licensed: L10n.t(.licLicensed)
        case .locked(let reason): title(reason)
        }
    }

    /// Only the last four characters of a License key are ever shown.
    static func masked(_ licenseKey: String) -> String {
        "••••\(licenseKey.suffix(4))"
    }

    static func openCheckout() {
        guard let url = LicensingConfig.checkoutURL else { return }
        NSWorkspace.shared.open(url)
    }
}

/// License key field with its Activate button and, below, the error of the
/// last attempt in plain words.
struct LicenseKeyEntry: View {
    var access: Access

    @State private var key = ""
    @State private var isActivating = false
    @State private var error: AccessError?

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(L10n.t(.licKeyPlaceholder), text: $key)
                    .textFieldStyle(.plain)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textPrimary)
                    .onSubmit(activate)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                PillButton(L10n.t(isActivating ? .licActivating : .licActivate), size: .small, action: activate)
                    .disabled(isActivating || trimmedKey.isEmpty)
            }
            if let error {
                Text(LicenseText.message(error))
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.critical.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func activate() {
        guard !isActivating, !trimmedKey.isEmpty else { return }
        isActivating = true
        error = nil
        Task {
            do {
                try await access.activate(licenseKey: trimmedKey)
                key = ""
            } catch {
                self.error = error as? AccessError ?? .noConnection
            }
            isActivating = false
        }
    }
}

/// The only thing the widget shows while Pocket is locked: why, a way to
/// buy a License, and a field for the License key.
struct LockScreenView: View {
    var access: Access

    private var reason: LockReason? {
        if case .locked(let reason) = access.state { return reason }
        return nil
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: "lock.fill")
                .font(Theme.iconLargeFont)
                .foregroundStyle(Theme.textSecondary)
            if access.isRefreshing {
                Text(L10n.t(.licChecking))
                    .font(Theme.headlineFont)
                    .foregroundStyle(Theme.textSecondary)
            } else if let reason {
                VStack(spacing: 6) {
                    Text(LicenseText.title(reason))
                        .font(Theme.titleFont)
                        .foregroundStyle(Theme.textPrimary)
                    Text(LicenseText.detail(reason))
                        .font(Theme.subFont)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    PillButton(L10n.t(.licBuy), style: .primary, action: LicenseText.openCheckout)
                    if reason != .trialEnded {
                        PillButton(L10n.t(.licTryAgain), systemName: "arrow.clockwise") {
                            Task { await access.refresh() }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t(.licEnterKey))
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.textTertiary)
                LicenseKeyEntry(access: access)
            }
        }
        .padding(Theme.panelInset + 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Settings → License: the Trial or License status, the key field, and
/// deactivation of this Mac.
struct LicenseSettingsView: View {
    var access: Access
    let isEnforced: Bool

    @State private var confirmingDeactivation = false
    @State private var isDeactivating = false
    @State private var deactivationFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(L10n.t(.licSection))
            SettingsCard {
                if isEnforced {
                    rows
                } else {
                    // Developer-only row, never in a release build.
                    SettingRow(
                        title: "Licensing is skipped in debug builds",
                        subtitle: "Launch with --licensing to exercise the real flow"
                    ) { EmptyView() }
                }
            }
        }
        .animation(Theme.stateSpring, value: access.state)
        .animation(Theme.stateSpring, value: confirmingDeactivation)
    }

    @ViewBuilder
    private var rows: some View {
        SettingRow(title: L10n.t(.licStatus), subtitle: LicenseText.status(access.state)) {
            if access.licenseKey == nil {
                PillButton(L10n.t(.licBuy), size: .small, action: LicenseText.openCheckout)
            }
        }
        Hairline(color: Palette.hairline)
        if let key = access.licenseKey {
            SettingRow(title: L10n.t(.licKeyLabel)) {
                Text(LicenseText.masked(key))
                    .font(Theme.smallValueFont)
                    .foregroundStyle(Palette.ink60)
            }
            Hairline(color: Palette.hairline)
            SettingRow(
                title: L10n.t(.licDeactivate),
                subtitle: deactivationFailed ? L10n.t(.licDeactivateFailed) : L10n.t(.licDeactivateSub)
            ) {
                deactivateControl
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t(.licEnterKey))
                    .font(Theme.bodyFont)
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.ink)
                LicenseKeyEntry(access: access)
            }
            .padding(.vertical, 12)
        }
    }

    /// Two steps in place — a sheet would hang out of the capsule.
    @ViewBuilder
    private var deactivateControl: some View {
        if confirmingDeactivation {
            HStack(spacing: 10) {
                Text(L10n.t(.licDeactivateConfirm))
                    .font(Theme.subFont)
                    .foregroundStyle(Palette.ink60)
                PaletteButton(L10n.t(.mailCancel), color: Palette.ink60) {
                    confirmingDeactivation = false
                }
                PaletteButton(L10n.t(.licDeactivate), color: Theme.critical.opacity(0.9), action: deactivate)
                    .disabled(isDeactivating)
            }
        } else {
            PaletteButton(L10n.t(.licDeactivate), color: Theme.critical.opacity(0.9)) {
                deactivationFailed = false
                confirmingDeactivation = true
            }
        }
    }

    private func deactivate() {
        isDeactivating = true
        Task {
            do {
                try await access.deactivate()
            } catch {
                deactivationFailed = true
            }
            isDeactivating = false
            confirmingDeactivation = false
        }
    }
}
