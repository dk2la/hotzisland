import SwiftUI

/// Account form for the Settings → Accounts page: provider preset prefills
/// hosts, password goes straight to the Keychain on save.
struct EmailSetupView: View {
    var service: EmailService
    let palette: WindowPalette

    @State private var provider: EmailProvider = .gmail
    @State private var email = ""
    @State private var password = ""
    @State private var imapHost = ""
    @State private var imapPort = "993"
    @State private var smtpHost = ""
    @State private var smtpPort = "465"
    @State private var checkState: SetupCheckState = .idle
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow(title: L10n.t(.mailProvider), palette: palette) {
                WindowSegmented(
                    options: EmailProvider.allCases.map { ($0, $0.title) },
                    selection: Binding(
                        get: { provider },
                        set: { applyPreset($0) }
                    ),
                    palette: palette
                )
            }
            if provider.isPasswordAuthUnreliable {
                Text(L10n.t(.mailOutlookWarning))
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.critical.opacity(0.9))
                    .padding(.bottom, 8)
            }
            Hairline(color: palette.hairline)
            SetupFieldRow(title: L10n.t(.mailAddress), palette: palette) {
                TextField("name@example.com", text: $email)
            }
            Hairline(color: palette.hairline)
            SetupFieldRow(
                title: L10n.t(.mailPassword),
                subtitle: L10n.t(.mailPasswordHint),
                palette: palette,
                width: 200
            ) {
                SecureField("", text: $password)
            }
            if provider == .custom {
                Hairline(color: palette.hairline)
                SetupFieldRow(title: L10n.t(.mailImapHost), palette: palette) {
                    TextField("imap.example.com", text: $imapHost)
                    TextField("993", text: $imapPort).frame(width: 56)
                }
                Hairline(color: palette.hairline)
                SetupFieldRow(title: L10n.t(.mailSmtpHost), palette: palette) {
                    TextField("smtp.example.com", text: $smtpHost)
                    TextField("465", text: $smtpPort).frame(width: 56)
                }
            }
            Hairline(color: palette.hairline)
            SetupActionRow(
                palette: palette,
                checkState: checkState,
                canCheck: isComplete,
                canSave: isComplete && !password.isEmpty,
                showRemove: service.config != nil,
                onCheck: runCheck,
                onRemove: {
                    service.removeAccount()
                    password = ""
                },
                onSave: { service.saveAccount(builtConfig, password: password) }
            )
        }
        .onAppear(perform: loadExisting)
    }

    // MARK: - State

    private var isComplete: Bool {
        !email.isEmpty && !resolvedConfig.imapHost.isEmpty && !resolvedConfig.smtpHost.isEmpty
    }

    private var resolvedConfig: (imapHost: String, imapPort: UInt16, smtpHost: String, smtpPort: UInt16, startTLS: Bool) {
        if let preset = provider.preset {
            return preset
        }
        return (
            imapHost,
            UInt16(imapPort) ?? 993,
            smtpHost,
            UInt16(smtpPort) ?? 465,
            (UInt16(smtpPort) ?? 465) == 587
        )
    }

    private var builtConfig: EmailAccountConfig {
        let resolved = resolvedConfig
        return EmailAccountConfig(
            email: email.trimmingCharacters(in: .whitespaces),
            imapHost: resolved.imapHost,
            imapPort: resolved.imapPort,
            smtpHost: resolved.smtpHost,
            smtpPort: resolved.smtpPort,
            smtpUsesSTARTTLS: resolved.startTLS,
            presetID: provider.rawValue
        )
    }

    private func applyPreset(_ newProvider: EmailProvider) {
        provider = newProvider
        checkState = .idle
        if let preset = newProvider.preset {
            imapHost = preset.0
            imapPort = String(preset.1)
            smtpHost = preset.2
            smtpPort = String(preset.3)
        }
    }

    private func loadExisting() {
        guard !loaded else { return }
        loaded = true
        guard let config = service.config else {
            applyPreset(.gmail)
            return
        }
        email = config.email
        provider = EmailProvider(rawValue: config.presetID) ?? .custom
        imapHost = config.imapHost
        imapPort = String(config.imapPort)
        smtpHost = config.smtpHost
        smtpPort = String(config.smtpPort)
    }

    private func runCheck() {
        let config = builtConfig
        let secret = password
        checkState = .checking
        Task {
            let result = await EmailService.testConnection(config, password: secret)
            switch result {
            case .success:
                checkState = .ok
            case .failure(let error):
                checkState = .failed(error.localizedDescription)
            }
        }
    }
}
