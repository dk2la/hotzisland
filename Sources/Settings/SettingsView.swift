import AppKit
import SwiftUI

/// Settings UI, hosted inside the expanded island (see IslandSettingsView).
/// Always the dark rack — matches the widget and the notch. Sidebar of icon
/// rows on the left, pages on the right, fully localized. Sized by its
/// host, not itself.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    var services: ModuleServices
    var pageSelection: SettingsPageSelection

    private var playbooks: PlaybookStore { services.playbookStore }

    @State private var editingPlaybook: Playbook?
    @State private var creatingPlaybook = false

    enum Page: String, CaseIterable, Identifiable {
        case general
        case appearance
        case modules
        case accounts
        case playbooks
        case hotkeys

        var id: String { rawValue }

        private var spec: (title: L10nKey, icon: String) {
            switch self {
            case .general: (.setGeneral, "gearshape")
            case .appearance: (.setAppearance, "circle.lefthalf.filled")
            case .modules: (.setModules, "square.grid.2x2")
            case .accounts: (.setAccounts, "at")
            case .playbooks: (.modPlaybooks, "bolt.fill")
            case .hotkeys: (.setHotkeys, "keyboard")
            }
        }

        @MainActor var title: String { L10n.t(spec.title) }
        var icon: String { spec.icon }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
                .background(Palette.panel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.desk)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("HotzIsland")
                .font(Theme.titleFont)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .padding(.top, 18)
            InstrumentLabel(L10n.t(.setTitle), color: Palette.ink40)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            ForEach(Page.allCases) { item in
                let isActive = pageSelection.page == item
                Button {
                    pageSelection.page = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 18)
                        Text(item.title)
                            .font(Theme.bodyFont)
                    }
                    .foregroundStyle(isActive ? Palette.accent : Palette.ink60)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        isActive ? Palette.accentWash : .clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
            Spacer(minLength: 0)
            Text("v\(Self.version) · MIT")
                .font(Theme.labelFont)
                .kerning(1)
                .foregroundStyle(Palette.ink40)
                .padding(14)
        }
        .padding(.horizontal, 8)
        .frame(width: 180)
        .background(Palette.desk)
    }

    // MARK: - Pages

    @ViewBuilder
    private var content: some View {
        switch pageSelection.page {
        case .general: generalPage
        case .appearance: appearancePage
        case .modules: modulesPage
        case .accounts: accountsPage
        case .playbooks: playbooksPage
        case .hotkeys: hotkeysPage
        }
    }

    private var accountsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(L10n.t(.modEmail))
                    EmailSetupView(service: services.emailService)
                    sectionHeader(L10n.t(.modAssistant))
                        .padding(.top, 18)
                    AssistantSetupView(assistant: services.assistantService)
                }
            }
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(L10n.t(.setBehavior))
            SettingRow(title: L10n.t(.setLanguage), subtitle: L10n.t(.setLanguageSub)) {
                languagePicker
            }
            Hairline(color: Palette.hairline)
            SettingRow(title: L10n.t(.setLaunch), subtitle: L10n.t(.setLaunchSub)) {
                InstrumentToggle(
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    )
                )
            }
            Hairline(color: Palette.hairline)
            SettingRow(title: L10n.t(.setOutsideClick), subtitle: L10n.t(.setOutsideClickSub)) {
                InstrumentToggle(isOn: $settings.closeOnOutsideClick)
            }
            Hairline(color: Palette.hairline)
            SettingRow(title: L10n.t(.setIdle), subtitle: L10n.t(.setIdleSub)) {
                WindowSegmented(
                    options: [
                        (IdleMode.invisible, L10n.t(.setIdleInvisible)),
                        (IdleMode.compact, L10n.t(.setIdleCompact)),
                    ],
                    selection: $settings.idleMode
                )
            }
            demoSection
        }
    }

    /// Demo mode toggle and, while it is on, one button per sample island
    /// event — everything a promo recording needs from one page.
    private var demoSection: some View {
        let demo = services.demo
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader(L10n.t(.setDemoSection))
                .padding(.top, 18)
            SettingRow(title: L10n.t(.setDemo), subtitle: L10n.t(.setDemoSub)) {
                InstrumentToggle(
                    isOn: Binding(
                        get: { demo.isActive },
                        set: { demo.setActive($0) }
                    )
                )
            }
            if demo.isActive {
                Hairline(color: Palette.hairline)
                SettingRow(title: L10n.t(.setDemoEvents), subtitle: L10n.t(.setDemoEventsSub)) {
                    HStack(spacing: 5) {
                        ForEach(DemoMode.sampleEvents, id: \.label) { sample in
                            Button {
                                demo.fire(sample.event)
                            } label: {
                                Text(sample.label)
                                    .font(Theme.labelFont)
                                    .kerning(1)
                                    .foregroundStyle(Palette.ink)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
        }
        .animation(Theme.stateSpring, value: demo.isActive)
    }

    private var languagePicker: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    settings.language = lang
                } label: {
                    if settings.language == lang {
                        Label(lang.title, systemImage: "checkmark")
                    } else {
                        Text(lang.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(settings.language.title)
                    .font(Theme.subFont)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(L10n.t(.setShellTheme))
            SettingRow(title: L10n.t(.setCapsule), subtitle: L10n.t(.setCapsuleSub)) {
                WindowSegmented(
                    options: [
                        (IslandTheme.stealth, "Stealth"),
                        (IslandTheme.glass, "Glass"),
                        (IslandTheme.glow, "Glow"),
                    ],
                    selection: $settings.theme
                )
            }
            Hairline(color: Palette.hairline)
            SettingRow(title: L10n.t(.setWidgetMaterial), subtitle: L10n.t(.setWidgetMaterialSub)) {
                WindowSegmented(
                    options: [
                        (GlassAppearance.light, L10n.t(.setLight)),
                        (GlassAppearance.dark, L10n.t(.setDark)),
                        (GlassAppearance.auto, L10n.t(.setAuto)),
                    ],
                    selection: $settings.glassAppearance
                )
            }
        }
    }

    private var modulesPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(L10n.t(.setModules))
            Text(L10n.t(.setModulesHint))
                .font(Theme.subFont)
                .foregroundStyle(Palette.ink40)
                .padding(.bottom, 10)
            ModulesOrderList(settings: settings)
            Hairline(color: Palette.hairline)
            SettingRow(title: L10n.t(.notesFolder), subtitle: services.notesStore.folderURL.path) {
                PaletteButton(L10n.t(.notesChange)) {
                    services.notesStore.pickFolder(activating: false)
                }
            }
        }
    }

    /// The editor replaces the page in place: a sheet would hang out of the
    /// island and fight its hover tracking.
    @ViewBuilder
    private var playbooksPage: some View {
        if creatingPlaybook {
            PlaybookEditorView(store: playbooks, existing: nil) {
                creatingPlaybook = false
            }
            .id("new")
        } else if let playbook = editingPlaybook {
            PlaybookEditorView(store: playbooks, existing: playbook) {
                editingPlaybook = nil
            }
            .id(playbook.id)
        } else {
            playbooksList
        }
    }

    private var playbooksList: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(L10n.t(.modPlaybooks))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(playbooks.playbooks) { playbook in
                        HStack(spacing: 10) {
                            Image(systemName: playbook.icon)
                                .font(Theme.iconSmallFont)
                                .foregroundStyle(Palette.accent)
                                .frame(width: 20)
                            Text(playbook.name)
                                .font(Theme.bodyFont)
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: 0)
                            PaletteButton(L10n.t(.calEdit)) {
                                editingPlaybook = playbook
                            }
                        }
                        .padding(.vertical, 10)
                        if playbook.id != playbooks.playbooks.last?.id {
                            Hairline(color: Palette.hairline)
                        }
                    }
                }
            }
            PaletteButton(L10n.t(.playAdd), vPad: 8) {
                creatingPlaybook = true
            }
        }
    }

    private var hotkeysPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(L10n.t(.setHotkeys))
            SettingRow(title: L10n.t(.setOpenSettings)) {
                HStack(spacing: 5) {
                    KeyCap(symbol: "⌘")
                    KeyCap(symbol: ",")
                }
            }
            Hairline(color: Palette.hairline)
            SettingRow(title: L10n.t(.setExpandIsland), subtitle: L10n.t(.setExpandIslandSub)) {
                KeyCap(symbol: "click")
            }
            Hairline(color: Palette.hairline)
            SettingRow(title: L10n.t(.setHideWidget), subtitle: L10n.t(.setHideWidgetSub)) {
                keyCaps(HotkeyService.Action.toggleWidgetHidden.keyCaps)
            }
            Hairline(color: Palette.hairline)
            SettingRow(title: L10n.t(.setPinPanel), subtitle: L10n.t(.setPinPanelSub)) {
                keyCaps(HotkeyService.Action.togglePanelPin.keyCaps)
            }
            Hairline(color: Palette.hairline)
            SettingRow(title: L10n.t(.setModeToggle), subtitle: L10n.t(.setModeToggleSub)) {
                keyCaps(HotkeyService.Action.toggleSettings.keyCaps)
            }
        }
    }

    private func keyCaps(_ symbols: [String]) -> some View {
        HStack(spacing: 5) {
            ForEach(symbols, id: \.self) { symbol in
                KeyCap(symbol: symbol)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        InstrumentLabel(title, color: Palette.ink40)
            .padding(.bottom, 12)
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}

/// Drag-to-reorder module list with enable toggles — shared by settings
/// and onboarding step 3.
struct ModulesOrderList: View {
    @Bindable var settings: AppSettings

    var body: some View {
        List {
            ForEach(settings.tabOrder) { tab in
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.ink40)
                    Image(systemName: tab.icon)
                        .font(Theme.iconSmallFont)
                        .foregroundStyle(Palette.ink60)
                        .frame(width: 20)
                    Text(tab.title)
                        .font(Theme.bodyFont)
                        .foregroundStyle(Palette.ink)
                    if tab.isComingSoon {
                        Text(L10n.t(.setSoonTag))
                            .font(Theme.subFont)
                            .foregroundStyle(Palette.ink40)
                    } else if NotchTab.defaultTabs.contains(tab) {
                        Text(L10n.t(.setDefaultTag))
                            .font(Theme.subFont)
                            .foregroundStyle(Palette.ink40)
                    }
                    Spacer(minLength: 0)
                    InstrumentToggle(
                        isOn: Binding(
                            get: { settings.isEnabled(tab) },
                            set: { _ in settings.toggle(tab) }
                        )
                    )
                    .disabled(settings.isEnabled(tab) && settings.enabledTabs.count == 1)
                }
                .listRowSeparatorTint(Palette.hairline)
                .listRowBackground(Color.clear)
            }
            .onMove { source, destination in
                settings.moveTabs(fromOffsets: source, toOffset: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
}

/// Shared page selection so module UI can deep-link into a settings page
/// (e.g. "Set up account" → Accounts).
@MainActor
@Observable
final class SettingsPageSelection {
    var page: SettingsView.Page = .general
}
