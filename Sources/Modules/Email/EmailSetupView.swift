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
    @State private var checkState: CheckState = .idle
    @State private var loaded = false

    enum CheckState: Equatable {
        case idle
        case checking
        case ok
        case failed(String)
    }

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
            fieldRow(L10n.t(.mailAddress)) {
                TextField("name@example.com", text: $email)
            }
            Hairline(color: palette.hairline)
            SettingRow(
                title: L10n.t(.mailPassword),
                subtitle: L10n.t(.mailPasswordHint),
                palette: palette
            ) {
                SecureField("", text: $password)
                    .textFieldStyle(.plain)
                    .font(Theme.bodyFont)
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(width: 200)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            if provider == .custom {
                Hairline(color: palette.hairline)
                fieldRow(L10n.t(.mailImapHost)) {
                    TextField("imap.example.com", text: $imapHost)
                    TextField("993", text: $imapPort).frame(width: 56)
                }
                Hairline(color: palette.hairline)
                fieldRow(L10n.t(.mailSmtpHost)) {
                    TextField("smtp.example.com", text: $smtpHost)
                    TextField("465", text: $smtpPort).frame(width: 56)
                }
            }
            Hairline(color: palette.hairline)
            actionRow
        }
        .onAppear(perform: loadExisting)
    }

    private func fieldRow(_ title: String, @ViewBuilder fields: @escaping () -> some View) -> some View {
        SettingRow(title: title, palette: palette) {
            HStack(spacing: 6) {
                fields()
            }
            .textFieldStyle(.plain)
            .font(Theme.bodyFont)
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(width: 260)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                runCheck()
            } label: {
                Text(checkLabel)
                    .font(Theme.subFont)
                    .foregroundStyle(checkColor)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .disabled(checkState == .checking || !isComplete)
            Spacer(minLength: 0)
            if service.config != nil {
                Button {
                    service.removeAccount()
                    password = ""
                } label: {
                    Text(L10n.t(.mailRemove))
                        .font(Theme.subFont)
                        .foregroundStyle(Theme.critical.opacity(0.9))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
            Button {
                service.saveAccount(builtConfig, password: password)
            } label: {
                Text(L10n.t(.mailSave))
                    .font(Theme.subFont)
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(palette.accentWash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .disabled(!isComplete || password.isEmpty)
        }
        .padding(.top, 12)
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

    private var checkLabel: String {
        switch checkState {
        case .idle: L10n.t(.mailCheck)
        case .checking: L10n.t(.mailChecking)
        case .ok: L10n.t(.mailCheckOk)
        case .failed(let message): message
        }
    }

    private var checkColor: Color {
        switch checkState {
        case .failed: Theme.critical.opacity(0.9)
        case .ok: palette.accent
        case .idle, .checking: palette.ink60
        }
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
