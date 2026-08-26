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
    @State private var checkState: SetupCheckState = .idle
    /// Resolved on appear and on provider switches — probing the filesystem
    /// from `body` would re-stat the PATH on every keystroke.
    @State private var cliInstalled = true
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow(title: L10n.t(.mailProvider), subtitle: providerHint, palette: palette) {
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
            SetupActionRow(
                palette: palette,
                checkState: checkState,
                canCheck: isComplete,
                canSave: isComplete,
                showRemove: assistant.config != nil,
                onCheck: runCheck,
                onRemove: {
                    assistant.removeConfig()
                    key = ""
                },
                onSave: { assistant.saveConfig(builtConfig, key: key) }
            )
        }
        .onAppear(perform: loadExisting)
    }

    // MARK: - Sections

    @ViewBuilder
    private var cliSection: some View {
        if !cliInstalled {
            Text(L10n.f(.asstCLIMissing, provider.executableName ?? ""))
                .font(Theme.subFont)
                .foregroundStyle(Theme.critical.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
        }
        Hairline(color: palette.hairline)
        SetupFieldRow(title: L10n.t(.asstModel), subtitle: L10n.t(.asstModelOptional), palette: palette) {
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
        SetupFieldRow(title: L10n.t(.asstBaseURL), palette: palette) {
            TextField(AssistantConfig.defaultBaseURL, text: $baseURL)
        }
        Hairline(color: palette.hairline)
        SetupFieldRow(title: L10n.t(.asstModel), palette: palette) {
            TextField(AssistantAPIPreset.matching(baseURL)?.sampleModel ?? "gpt-5-mini", text: $model)
        }
        Hairline(color: palette.hairline)
        SetupFieldRow(title: L10n.t(.asstKey), subtitle: L10n.t(.asstKeyHint), palette: palette, width: 200) {
            SecureField("", text: $key)
        }
    }

    // MARK: - State

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

    private func refreshCLIInstalled() {
        cliInstalled = !provider.isCLI
            || CLIAssistantClient(provider: provider, model: "").isInstalled
    }

    private func switchProvider(_ newProvider: AssistantProvider) {
        provider = newProvider
        checkState = .idle
        refreshCLIInstalled()
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
        if let config = assistant.config {
            provider = config.provider
            baseURL = config.baseURL
            model = config.model
        }
        refreshCLIInstalled()
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
