import AppKit
import SwiftUI

/// Settings UI, hosted inside the expanded island (see IslandSettingsView).
/// Drawn on the island's glass — the widget's material — with nothing
/// opaque in between: a lighter sidebar of pages on the left, the page on
/// the right as a titled stack of grouped cards. Fully localized; sized by
/// its host, not itself.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    var services: ModuleServices
    var pageSelection: SettingsPageSelection
    /// Set when the settings were opened from the tour — the sidebar then
    /// leads with "‹ Back" to the page the tour left.
    var onBack: (() -> Void)?

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

        private var spec: (title: L10nKey, subtitle: L10nKey, icon: String) {
            switch self {
            case .general: (.setGeneral, .setGeneralSub, "gearshape")
            case .appearance: (.setAppearance, .setAppearanceSub, "circle.lefthalf.filled")
            case .modules: (.setModules, .setModulesSub, "square.grid.2x2")
            case .accounts: (.setAccounts, .setAccountsSub, "at")
            case .playbooks: (.modPlaybooks, .setPlaybooksSub, "bolt.fill")
            case .hotkeys: (.setHotkeys, .setHotkeysSub, "command")
            }
        }

        @MainActor var title: String { L10n.t(spec.title) }
        @MainActor var subtitle: String { L10n.t(spec.subtitle) }
        var icon: String { spec.icon }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            page
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                if let onBack {
                    PillButton(L10n.t(.obBack), systemName: "chevron.left", size: .small, action: onBack)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
                Text(L10n.t(.setTitle))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
            .frame(height: 30)
            .padding(.horizontal, 8)
            .padding(.top, 16)
            .padding(.bottom, 16)
            ForEach(Page.allCases) { item in
                SidebarRow(page: item, isActive: pageSelection.page == item) {
                    pageSelection.page = item
                }
            }
            Spacer(minLength: 0)
            Text("HotzIsland \(Self.version)")
                .font(Theme.captionFont)
                .foregroundStyle(Palette.ink40)
                .padding(.horizontal, 10)
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 12)
        .frame(width: 200)
        .frame(maxHeight: .infinity)
        .background(Palette.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 1)
        }
        .animation(Theme.stateSpring, value: onBack != nil)
    }

    // MARK: - Page

    /// The playbook editor brings its own title row; every other page gets
    /// the big title and a line on what it is for.
    private var showsPageHeader: Bool {
        !(pageSelection.page == .playbooks && (creatingPlaybook || editingPlaybook != nil))
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsPageHeader {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pageSelection.page.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(pageSelection.page.subtitle)
                        .font(Theme.bodyFont)
                        .foregroundStyle(Palette.ink40)
                }
                // The close button floats over the top-right corner.
                .padding(.trailing, 40)
                .padding(.bottom, 20)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

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

    /// Titled card sections, scrolling once they outgrow the panel.
    private func sections<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                content()
            }
            .padding(.bottom, 8)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ rows: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(title)
            SettingsCard(content: rows)
        }
    }

    // MARK: General

    private var generalPage: some View {
        sections {
            section(L10n.t(.setBehavior)) {
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
            }
            // The welcome tour: replay it now, or have it greet every launch.
            section(L10n.t(.obTour)) {
                SettingRow(title: L10n.t(.obTour), subtitle: L10n.t(.obTourSub)) {
                    PillButton(L10n.t(.obShow), systemName: "play.fill", size: .small) {
                        requestOnboarding()
                    }
                }
                Hairline(color: Palette.hairline)
                SettingRow(title: L10n.t(.obShowAtLaunch), subtitle: L10n.t(.obShowAtLaunchSub)) {
                    InstrumentToggle(isOn: $settings.showOnboardingAtLaunch)
                }
            }
            demoSection
        }
    }

    /// Demo mode toggle and, while it is on, one button per sample island
    /// event — everything a promo recording needs from one page.
    private var demoSection: some View {
        let demo = services.demo
        return section(L10n.t(.setDemoSection)) {
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
                            PillButton(sample.label, size: .small) {
                                demo.fire(sample.event)
                            }
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
                    .fontWeight(.medium)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(Theme.textPrimary.opacity(0.10)))
            .overlay(Capsule().strokeBorder(Theme.textPrimary.opacity(0.12), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Appearance

    private var appearancePage: some View {
        sections {
            section(L10n.t(.setShellTheme)) {
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
    }

    // MARK: Modules

    /// Not a scroll of cards: the order list scrolls itself and takes all
    /// the height the page has.
    private var modulesPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSectionHeader(L10n.t(.setModulesHint))
                SettingsCard {
                    ModulesOrderList(settings: settings)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            SettingsCard {
                SettingRow(
                    title: L10n.t(.notesFolder),
                    subtitle: services.notesStore.folderURL.path
                        .replacingOccurrences(of: NSHomeDirectory(), with: "~")
                ) {
                    PillButton(L10n.t(.notesChange), size: .small) {
                        services.notesStore.pickFolder(activating: false)
                    }
                }
            }
        }
    }

    // MARK: Accounts

    private var accountsPage: some View {
        sections {
            section(L10n.t(.modEmail)) {
                EmailSetupView(service: services.emailService)
                    .padding(.bottom, 12)
            }
            section(L10n.t(.modAssistant)) {
                AssistantSetupView(assistant: services.assistantService)
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: Playbooks

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
        sections {
            VStack(alignment: .leading, spacing: 12) {
                if !playbooks.playbooks.isEmpty {
                    SettingsCard {
                        ForEach(playbooks.playbooks) { playbook in
                            HStack(spacing: 12) {
                                Image(systemName: playbook.icon)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                    .frame(width: 30, height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(Palette.raised)
                                    )
                                Text(playbook.name)
                                    .font(Theme.bodyFont)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Palette.ink)
                                Spacer(minLength: 0)
                                PillButton(L10n.t(.calEdit), size: .small) {
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
                PillButton(L10n.t(.playAdd), systemName: "plus") {
                    creatingPlaybook = true
                }
            }
        }
    }

    // MARK: Hotkeys

    private var hotkeysPage: some View {
        sections {
            section(L10n.t(.hkBuiltIn)) {
                SettingRow(title: L10n.t(.setOpenSettings)) {
                    keyCaps(["⌘", ","])
                }
                Hairline(color: Palette.hairline)
                SettingRow(title: L10n.t(.setExpandIsland), subtitle: L10n.t(.setExpandIslandSub)) {
                    KeyCap(symbol: "click")
                }
            }
            // The global ones are the user's to rebind.
            VStack(alignment: .leading, spacing: 0) {
                SettingsSectionHeader(L10n.t(.hkGlobal))
                SettingsCard {
                    SettingRow(title: L10n.t(.setHideWidget), subtitle: L10n.t(.setHideWidgetSub)) {
                        HotkeyRecorder(action: .toggleWidgetHidden, hotkeys: services.hotkeys)
                    }
                    Hairline(color: Palette.hairline)
                    SettingRow(title: L10n.t(.setPinPanel), subtitle: L10n.t(.setPinPanelSub)) {
                        HotkeyRecorder(action: .togglePanelPin, hotkeys: services.hotkeys)
                    }
                    Hairline(color: Palette.hairline)
                    SettingRow(title: L10n.t(.setModeToggle), subtitle: L10n.t(.setModeToggleSub)) {
                        HotkeyRecorder(action: .toggleSettings, hotkeys: services.hotkeys)
                    }
                }
                Text(L10n.t(.hkHint))
                    .font(Theme.captionFont)
                    .foregroundStyle(Palette.ink40)
                    .padding(.leading, 4)
                    .padding(.top, 8)
            }
        }
    }

    private func keyCaps(_ symbols: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(symbols, id: \.self) { symbol in
                KeyCap(symbol: symbol)
            }
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}

/// One sidebar page: icon and name; the open page sits on a raised glass
/// tile with its icon in the accent.
private struct SidebarRow: View {
    let page: SettingsView.Page
    let isActive: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: page.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isActive ? Palette.accent : Palette.ink60)
                    .frame(width: 18)
                Text(page.title)
                    .font(Theme.bodyFont)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? Palette.ink : Palette.ink60)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape.fill(Theme.textPrimary.opacity(isActive ? 0.09 : hovered ? 0.05 : 0))
            )
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

/// Drag-to-reorder module list with enable toggles (Settings → Modules).
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
                        .fontWeight(.medium)
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
                .padding(.vertical, 3)
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
