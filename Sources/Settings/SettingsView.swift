import EventKit
import SwiftUI

/// Settings window — "rack unit": sidebar of sections on the left, panels
/// on the right. Follows the system appearance: rack graphite in dark,
/// Paper in light (the island itself is always dark).
struct SettingsView: View {
    @Bindable var settings: AppSettings
    var playbooks: PlaybookStore

    @Environment(\.colorScheme) private var scheme
    @State private var page: Page = .general
    @State private var editingPlaybook: Playbook?
    @State private var creatingPlaybook = false

    enum Page: String, CaseIterable, Identifiable {
        case general = "Общие"
        case appearance = "Вид"
        case modules = "Модули"
        case playbooks = "Плейбуки"
        case hotkeys = "Хоткеи"

        var id: String { rawValue }
    }

    private var palette: WindowPalette { WindowPalette.current(scheme) }

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
        .frame(width: 680, height: 470)
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
        VStack(alignment: .leading, spacing: 2) {
            Text("Настройки")
                .font(Theme.titleFont)
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 14)
            ForEach(Page.allCases) { item in
                let isActive = page == item
                Button {
                    page = item
                } label: {
                    Text(item.rawValue)
                        .font(Theme.bodyFont)
                        .foregroundStyle(isActive ? palette.accent : palette.ink60)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            isActive ? palette.accentWash : .clear,
                            in: RoundedRectangle(cornerRadius: 6)
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
        .frame(width: 168)
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
            sectionHeader("Поведение")
            SettingRow(
                title: "Запускать при входе",
                subtitle: "Агент меню-бара, без иконки в доке",
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
                title: "Режим покоя",
                subtitle: "Что видно, когда ничего не происходит",
                palette: palette
            ) {
                WindowSegmented(
                    options: [(IdleMode.invisible, "Невидим"), (IdleMode.compact, "Индикаторы")],
                    selection: Binding(
                        get: { settings.idleMode },
                        set: { settings.idleMode = $0 }
                    ),
                    palette: palette
                )
            }
        }
    }

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Тема оболочки")
            SettingRow(
                title: "Капсула",
                subtitle: "Влияет только на остров — окна следуют системной теме",
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
        }
    }

    private var modulesPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Каналы")
            Text("Порядок — перетаскиванием. Последний включённый канал выключить нельзя.")
                .font(Theme.subFont)
                .foregroundStyle(palette.ink40)
                .padding(.bottom, 10)
            ModulesOrderList(settings: settings, palette: palette)
        }
    }

    private var playbooksPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Плейбуки")
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
                                Text("Изменить")
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
                Text("Добавить плейбук…")
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
            sectionHeader("Хоткеи")
            SettingRow(title: "Открыть настройки", palette: palette) {
                HStack(spacing: 5) {
                    KeyCap(symbol: "⌘", palette: palette)
                    KeyCap(symbol: ",", palette: palette)
                }
            }
            Hairline(color: palette.hairline)
            SettingRow(
                title: "Раскрыть остров",
                subtitle: "Наведение курсора на вырез",
                palette: palette
            ) {
                KeyCap(symbol: "hover", palette: palette)
            }
            Hairline(color: palette.hairline)
            Text("Настраиваемые сочетания — в планах.")
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

/// Drag-to-reorder channel list with enable toggles — shared by settings
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
                    InstrumentLabel(tab.channelLabel, color: palette.ink60)
                    Text(tab.title)
                        .font(Theme.subFont)
                        .foregroundStyle(palette.ink40)
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
