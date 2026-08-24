import EventKit
import SwiftUI

/// Settings window, V3: always the dark rack — matches the widget and the
/// notch. Sidebar of icon rows on the left, pages on the right, acid-green
/// active states, fully localized.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    var playbooks: PlaybookStore

    @State private var page: Page = .general
    @State private var editingPlaybook: Playbook?
    @State private var creatingPlaybook = false

    enum Page: String, CaseIterable, Identifiable {
        case general
        case appearance
        case modules
        case playbooks
        case hotkeys

        var id: String { rawValue }

        @MainActor
        var title: String {
            switch self {
            case .general: L10n.t(.setGeneral)
            case .appearance: L10n.t(.setAppearance)
            case .modules: L10n.t(.setModules)
            case .playbooks: L10n.t(.setPlaybooks)
            case .hotkeys: L10n.t(.setHotkeys)
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "circle.lefthalf.filled"
            case .modules: "square.grid.2x2"
            case .playbooks: "bolt.fill"
            case .hotkeys: "keyboard"
            }
        }
    }

    private var palette: WindowPalette { WindowPalette.rack }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(palette.hairline)
                .frame(width: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
                .background(palette.panel)
        }
        .frame(width: 700, height: 490)
        .background(palette.desk)
        .sheet(item: $editingPlaybook) { playbook in
            PlaybookEditorView(store: playbooks, existing: playbook) {
                editingPlaybook = nil
            }
        }
        .sheet(isPresented: $creatingPlaybook) {
            PlaybookEditorView(store: playbooks, existing: nil) {
                creatingPlaybook = false
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("HotzIsland")
                .font(Theme.titleFont)
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 14)
                .padding(.top, 18)
            InstrumentLabel(L10n.t(.setTitle), color: palette.ink40)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            ForEach(Page.allCases) { item in
                let isActive = page == item
                Button {
                    page = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 18)
                        Text(item.title)
                            .font(Theme.bodyFont)
                    }
                    .foregroundStyle(isActive ? palette.accent : palette.ink60)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        isActive ? palette.accentWash : .clear,
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
                .foregroundStyle(palette.ink40)
                .padding(14)
        }
        .padding(.horizontal, 8)
        .frame(width: 180)
        .background(palette.desk)
    }

    // MARK: - Pages

    @ViewBuilder
    private var content: some View {
        switch page {
        case .general: generalPage
        case .appearance: appearancePage
        case .modules: modulesPage
        case .playbooks: playbooksPage
        case .hotkeys: hotkeysPage
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(L10n.t(.setBehavior))
            SettingRow(
                title: L10n.t(.setLanguage),
                subtitle: L10n.t(.setLanguageSub),
                palette: palette
            ) {
                languagePicker
            }
            Hairline(color: palette.hairline)
            SettingRow(
                title: L10n.t(.setLaunch),
                subtitle: L10n.t(.setLaunchSub),
                palette: palette
            ) {
                InstrumentToggle(
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    ),
                    palette: palette
                )
            }
            Hairline(color: palette.hairline)
            SettingRow(
                title: L10n.t(.setDisplayMode),
                subtitle: L10n.t(.setDisplayModeSub),
                palette: palette
            ) {
                WindowSegmented(
                    options: [
                        (DisplayMode.island, L10n.t(.setIsland)),
                        (DisplayMode.widget, L10n.t(.setWidget)),
                    ],
                    selection: Binding(
                        get: { settings.displayMode },
                        set: { settings.displayMode = $0 }
                    ),
                    palette: palette
                )
            }
            Hairline(color: palette.hairline)
            SettingRow(
                title: L10n.t(.setIdle),
                subtitle: L10n.t(.setIdleSub),
                palette: palette
            ) {
                WindowSegmented(
                    options: [
                        (IdleMode.invisible, L10n.t(.setIdleInvisible)),
                        (IdleMode.compact, L10n.t(.setIdleCompact)),
                    ],
                    selection: Binding(
                        get: { settings.idleMode },
                        set: { settings.idleMode = $0 }
                    ),
                    palette: palette
                )
            }
        }
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
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(L10n.t(.setShellTheme))
            SettingRow(
                title: L10n.t(.setCapsule),
                subtitle: L10n.t(.setCapsuleSub),
                palette: palette
            ) {
                WindowSegmented(
                    options: [
                        (IslandTheme.stealth, "Stealth"),
                        (IslandTheme.glass, "Glass"),
                        (IslandTheme.glow, "Glow"),
                    ],
                    selection: Binding(
                        get: { settings.theme },
                        set: { settings.theme = $0 }
                    ),
                    palette: palette
                )
            }
            Hairline(color: palette.hairline)
            SettingRow(
                title: L10n.t(.setWidgetMaterial),
                subtitle: L10n.t(.setWidgetMaterialSub),
                palette: palette
            ) {
                WindowSegmented(
                    options: [
                        (GlassAppearance.light, L10n.t(.setLight)),
                        (GlassAppearance.dark, L10n.t(.setDark)),
                        (GlassAppearance.auto, L10n.t(.setAuto)),
                    ],
                    selection: Binding(
                        get: { settings.glassAppearance },
                        set: { settings.glassAppearance = $0 }
                    ),
                    palette: palette
                )
            }
        }
    }

    private var modulesPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(L10n.t(.setModules))
            Text(L10n.t(.setModulesHint))
                .font(Theme.subFont)
                .foregroundStyle(palette.ink40)
                .padding(.bottom, 10)
            ModulesOrderList(settings: settings, palette: palette)
        }
    }

    private var playbooksPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(L10n.t(.setPlaybooks))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(playbooks.playbooks) { playbook in
                        HStack(spacing: 10) {
                            Image(systemName: playbook.icon)
                                .font(Theme.iconSmallFont)
                                .foregroundStyle(palette.accent)
                                .frame(width: 20)
                            Text(playbook.name)
                                .font(Theme.bodyFont)
                                .foregroundStyle(palette.ink)
                            Spacer(minLength: 0)
                            Button {
                                editingPlaybook = playbook
                            } label: {
                                Text(L10n.t(.playEdit))
                                    .font(Theme.subFont)
                                    .foregroundStyle(palette.accent)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle())
                        }
                        .padding(.vertical, 10)
                        if playbook.id != playbooks.playbooks.last?.id {
                            Hairline(color: palette.hairline)
                        }
                    }
                }
            }
            Button {
                creatingPlaybook = true
            } label: {
                Text(L10n.t(.playAdd))
                    .font(Theme.subFont)
                    .foregroundStyle(palette.accent)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var hotkeysPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(L10n.t(.setHotkeys))
            SettingRow(title: L10n.t(.setOpenSettings), palette: palette) {
                HStack(spacing: 5) {
                    KeyCap(symbol: "⌘", palette: palette)
                    KeyCap(symbol: ",", palette: palette)
                }
            }
            Hairline(color: palette.hairline)
            SettingRow(
                title: L10n.t(.setExpandIsland),
                subtitle: L10n.t(.setExpandIslandSub),
                palette: palette
            ) {
                KeyCap(symbol: "hover", palette: palette)
            }
            Hairline(color: palette.hairline)
            Text(L10n.t(.setHotkeysSoon))
                .font(Theme.subFont)
                .foregroundStyle(palette.ink40)
                .padding(.top, 14)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        InstrumentLabel(title, color: palette.ink40)
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
    let palette: WindowPalette

    var body: some View {
        List {
            ForEach(settings.tabOrder) { tab in
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.ink40)
                    Image(systemName: tab.icon)
                        .font(Theme.iconSmallFont)
                        .foregroundStyle(palette.ink60)
                        .frame(width: 20)
                    Text(tab.title)
                        .font(Theme.bodyFont)
                        .foregroundStyle(palette.ink)
                    if tab.isComingSoon {
                        Text(L10n.t(.setSoonTag))
                            .font(Theme.subFont)
                            .foregroundStyle(palette.ink40)
                    } else if NotchTab.defaultTabs.contains(tab) {
                        Text(L10n.t(.setDefaultTag))
                            .font(Theme.subFont)
                            .foregroundStyle(palette.ink40)
                    }
                    Spacer(minLength: 0)
                    InstrumentToggle(
                        isOn: Binding(
                            get: { settings.isEnabled(tab) },
                            set: { _ in settings.toggle(tab) }
                        ),
                        palette: palette
                    )
                    .disabled(settings.isEnabled(tab) && settings.enabledTabs.count == 1)
                }
                .listRowSeparatorTint(palette.hairline)
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
