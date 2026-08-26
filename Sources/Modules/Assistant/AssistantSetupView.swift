import SwiftUI

/// Provider form for the Settings → Accounts page. Two of the three
/// providers drive a locally installed CLI, which spends the user's chat
/// subscription; the third is any OpenAI-compatible HTTP endpoint.
struct AssistantSetupView: View {
    var assistant: AssistantService
    let palette: WindowPalette

    @State private var provider: AssistantProvider = .claudeCode
    @State private var baseURL = AssistantConfig.defaultBaseURL
    @State private var model = ""
    @State private var key = ""
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
            SettingRow(title: L10n.t(.asstProvider), subtitle: providerHint, palette: palette) {
                WindowSegmented(
                    options: AssistantProvider.allCases.map { ($0, $0.title) },
                    selection: Binding(get: { provider }, set: { switchProvider($0) }),
                    palette: palette
                )
            }
            if provider.isCLI {
                cliSection
            } else {
                apiSection
            }
            Hairline(color: palette.hairline)
            actionRow
        }
        .onAppear(perform: loadExisting)
    }

    // MARK: - Sections

    @ViewBuilder
    private var cliSection: some View {
        if !isCLIInstalled {
            Text(L10n.f(.asstCLIMissing, provider.executableName ?? ""))
                .font(Theme.subFont)
                .foregroundStyle(Theme.critical.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
        }
        Hairline(color: palette.hairline)
        fieldRow(L10n.t(.asstModel), subtitle: L10n.t(.asstModelOptional)) {
            TextField(provider == .claudeCode ? "opus" : "gpt-5", text: $model)
        }
    }

    @ViewBuilder
    private var apiSection: some View {
        Hairline(color: palette.hairline)
        SettingRow(title: L10n.t(.asstPreset), palette: palette) {
            HStack(spacing: 6) {
                ForEach(AssistantAPIPreset.allCases) { preset in
                    Button {
                        applyPreset(preset)
                    } label: {
                        Text(preset.title)
                            .font(Theme.labelFont)
                            .foregroundStyle(isActivePreset(preset) ? palette.accent : palette.ink60)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                isActivePreset(preset) ? palette.accentWash : palette.raised,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        Hairline(color: palette.hairline)
        fieldRow(L10n.t(.asstBaseURL)) {
            TextField(AssistantConfig.defaultBaseURL, text: $baseURL)
        }
        Hairline(color: palette.hairline)
        fieldRow(L10n.t(.asstModel)) {
            TextField(AssistantAPIPreset.matching(baseURL)?.sampleModel ?? "gpt-5-mini", text: $model)
        }
        Hairline(color: palette.hairline)
        SettingRow(title: L10n.t(.asstKey), subtitle: L10n.t(.asstKeyHint), palette: palette) {
            SecureField("", text: $key)
                .textFieldStyle(.plain)
                .font(Theme.bodyFont)
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(width: 200)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private func fieldRow(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder fields: @escaping () -> some View
    ) -> some View {
        SettingRow(title: title, subtitle: subtitle, palette: palette) {
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
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .disabled(checkState == .checking || !isComplete)
            Spacer(minLength: 0)
            if assistant.config != nil {
                Button {
                    assistant.removeConfig()
                    key = ""
                } label: {
                    Text(L10n.t(.mailRemove))
                        .font(Theme.subFont)
                        .foregroundStyle(Theme.critical.opacity(0.9))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
            Button {
                assistant.saveConfig(builtConfig, key: key)
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
            .disabled(!isComplete)
        }
        .padding(.top, 12)
    }

    // MARK: - State

    private var isCLIInstalled: Bool {
        CLIAssistantClient(provider: provider, model: "").isInstalled
    }

    private var providerHint: String {
        switch provider {
        case .claudeCode: L10n.t(.asstProviderClaude)
        case .codex: L10n.t(.asstProviderCodex)
        case .api: L10n.t(.asstProviderAPI)
        }
    }

    /// CLI providers need nothing typed — the CLI carries its own auth.
    private var isComplete: Bool {
        guard !provider.isCLI else { return true }
        return !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var builtConfig: AssistantConfig {
        AssistantConfig(
            provider: provider,
            baseURL: baseURL.trimmingCharacters(in: .whitespaces),
            model: model.trimmingCharacters(in: .whitespaces)
        )
    }

    private func isActivePreset(_ preset: AssistantAPIPreset) -> Bool {
        AssistantAPIPreset.matching(baseURL) == preset
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

    private func switchProvider(_ newProvider: AssistantProvider) {
        provider = newProvider
        checkState = .idle
        // Model names do not carry across providers.
        if newProvider.isCLI {
            model = ""
        } else if model.isEmpty {
            applyPreset(.openai)
        }
    }

    private func applyPreset(_ preset: AssistantAPIPreset) {
        baseURL = preset.baseURL
        model = preset.sampleModel
        checkState = .idle
    }

    private func loadExisting() {
        guard !loaded else { return }
        loaded = true
        guard let config = assistant.config else { return }
        provider = config.provider
        baseURL = config.baseURL
        model = config.model
    }

    private func runCheck() {
        let config = builtConfig
        let secret = key
        checkState = .checking
        Task {
            let result = await AssistantService.testConnection(config, key: secret)
            switch result {
            case .success:
                checkState = .ok
            case .failure(let error):
                checkState = .failed(error.localizedDescription)
            }
        }
    }
}
