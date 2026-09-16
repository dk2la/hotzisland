import AppKit
import SwiftUI

/// Editor sheet for a single playbook: name and icon on top, then the
/// ordered list of steps — one card each with its own fields, reorder and
/// remove controls — and an "Add step" menu. Drawn on the settings palette
/// so it reads as part of the Settings window, not a system form.
struct PlaybookEditorView: View {
    var store: PlaybookStore
    /// nil means "create new".
    var existing: Playbook?
    let onDone: () -> Void

    @State private var draft: Playbook
    @State private var apps: [InstalledApp] = []
    @State private var shortcuts: [String] = []
    /// Re-read when the app comes back to front — the user may have just
    /// flipped the switch in System Settings.
    @State private var accessibilityTrusted = false

    private let palette = WindowPalette.rack

    init(store: PlaybookStore, existing: Playbook?, onDone: @escaping () -> Void) {
        self.store = store
        self.existing = existing
        self.onDone = onDone
        _draft = State(initialValue: existing ?? Playbook(name: ""))
    }

    private static let icons = [
        "bolt.fill", "hammer.fill", "film.fill", "gamecontroller.fill",
        "book.fill", "moon.zzz.fill", "cup.and.saucer.fill", "paintbrush.fill",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    identitySection
                    stepsSection
                }
                .padding(20)
            }
            Hairline(color: palette.hairline)
            actionRow
                .padding(16)
        }
        // Sized by the settings page it replaces, not by itself.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.panel)
        .task {
            apps = await AppCatalog.discover()
        }
        .task {
            shortcuts = await ShortcutsCatalog.installedShortcuts()
        }
        .onAppear {
            accessibilityTrusted = WindowLayoutService.isTrusted
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityTrusted = WindowLayoutService.isTrusted
        }
    }

    // MARK: - Name + icon

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                InstrumentLabel(L10n.t(.playName), color: palette.ink40)
                    .frame(width: 60, alignment: .leading)
                PaletteTextField(placeholder: L10n.t(.playName), text: $draft.name, palette: palette)
            }
            HStack(spacing: 12) {
                InstrumentLabel(L10n.t(.playIcon), color: palette.ink40)
                    .frame(width: 60, alignment: .leading)
                HStack(spacing: 6) {
                    ForEach(Self.icons, id: \.self) { icon in
                        let isActive = draft.icon == icon
                        Button {
                            draft.icon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(Theme.iconSmallFont)
                                .foregroundStyle(isActive ? palette.accent : palette.ink60)
                                .frame(width: 30, height: 26)
                                .background(
                                    isActive ? palette.raised : palette.panel,
                                    in: RoundedRectangle(cornerRadius: 5)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(isActive ? palette.accent.opacity(0.5) : palette.border, lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            InstrumentLabel(L10n.t(.playSteps), color: palette.ink40)
            if draft.steps.isEmpty {
                Text(L10n.t(.playNoSteps))
                    .font(Theme.subFont)
                    .foregroundStyle(palette.ink40)
                    .padding(.vertical, 6)
            }
            ForEach($draft.steps) { $step in
                let index = draft.steps.firstIndex { $0.id == step.id } ?? 0
                PlaybookStepCard(
                    step: $step,
                    apps: apps,
                    shortcuts: shortcuts,
                    accessibilityTrusted: accessibilityTrusted,
                    palette: palette,
                    canMoveUp: index > 0,
                    canMoveDown: index < draft.steps.count - 1,
                    onMoveUp: { move(step.id, by: -1) },
                    onMoveDown: { move(step.id, by: 1) },
                    onRemove: { draft.steps.removeAll { $0.id == step.id } },
                    onGrantAccess: {
                        WindowLayoutService.requestAccess()
                        accessibilityTrusted = WindowLayoutService.isTrusted
                    }
                )
            }
            addStepMenu
                .padding(.top, 2)
        }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = draft.steps.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard draft.steps.indices.contains(target) else { return }
        draft.steps.swapAt(index, target)
    }

    private var addStepMenu: some View {
        Menu {
            ForEach(PlaybookStep.Kind.allCases, id: \.self) { kind in
                Button {
                    draft.steps.append(kind.makeStep())
                } label: {
                    Label(kind.title, systemImage: kind.icon)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text(L10n.t(.playAddStep))
                    .font(Theme.subFont)
            }
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(palette.accentWash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 10) {
            if let existing {
                Button {
                    store.remove(existing)
                    onDone()
                } label: {
                    Text(L10n.t(.calDelete))
                        .font(Theme.subFont)
                        .foregroundStyle(Theme.critical.opacity(0.9))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
            Spacer(minLength: 0)
            Button {
                onDone()
            } label: {
                Text(L10n.t(.mailCancel))
                    .font(Theme.subFont)
                    .foregroundStyle(palette.ink60)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut(.cancelAction)
            Button {
                save()
            } label: {
                Text(L10n.t(.calSave))
                    .font(Theme.subFont)
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(palette.accentWash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.4)
        }
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Trims what the user typed so the runner never sees blank lines or
    /// padded names.
    private func save() {
        var cleaned = draft
        cleaned.name = cleaned.name.trimmingCharacters(in: .whitespaces)
        cleaned.steps = cleaned.steps.map { step in
            switch step {
            case .runShortcut(let id, let name):
                .runShortcut(id: id, name: name.trimmingCharacters(in: .whitespaces))
            case .setFocus(let id, let name):
                .setFocus(id: id, shortcutName: name.trimmingCharacters(in: .whitespaces))
            case .openURLs(let id, let urls):
                .openURLs(
                    id: id,
                    urls: urls.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                )
            default:
                step
            }
        }
        if existing == nil {
            store.add(cleaned)
        } else {
            store.update(cleaned)
        }
        onDone()
    }
}

// MARK: - Step card

/// One step: kind label with move/remove controls on top, the kind's
/// fields underneath. Bindings into the enum payload are rebuilt per
/// field so the card never has to know the step's index.
private struct PlaybookStepCard: View {
    @Binding var step: PlaybookStep
    let apps: [InstalledApp]
    let shortcuts: [String]
    let accessibilityTrusted: Bool
    let palette: WindowPalette
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void
    let onGrantAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: step.kind.icon)
                    .font(Theme.iconSmallFont)
                    .foregroundStyle(palette.accent)
                    .frame(width: 18)
                Text(step.kind.title)
                    .font(Theme.bodyFont)
                    .fontWeight(.medium)
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 0)
                control("chevron.up", enabled: canMoveUp, action: onMoveUp)
                control("chevron.down", enabled: canMoveDown, action: onMoveDown)
                control("xmark", enabled: true, action: onRemove)
            }
            fields
        }
        .padding(12)
        .background(palette.desk, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        )
    }

    private func control(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.ink60)
                .frame(width: 22, height: 22)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }

    @ViewBuilder
    private var fields: some View {
        switch step {
        case .openApps:
            AppPickerView(apps: apps, selected: bundleIDs, palette: palette)
            layoutPicker
        case .closeOtherApps:
            EmptyView()
        case .runShortcut:
            shortcutPicker(shortcutName)
        case .setFocus:
            shortcutPicker(focusShortcutName)
        case .startTimer:
            HStack(spacing: 8) {
                PaletteTextField(placeholder: L10n.t(.playMinutes), text: minutesText, palette: palette)
                    .frame(width: 90)
                Text(L10n.t(.playMinutes).lowercased())
                    .font(Theme.subFont)
                    .foregroundStyle(palette.ink40)
            }
        case .openURLs:
            urlsEditor
        }
    }

    // MARK: Layout

    private var layoutPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(L10n.t(.playLayout))
                    .font(Theme.subFont)
                    .foregroundStyle(palette.ink60)
                Spacer(minLength: 0)
                Text(layout.wrappedValue.title)
                    .font(Theme.subFont)
                    .foregroundStyle(palette.ink40)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(WindowLayout.allCases) { option in
                        let isActive = layout.wrappedValue == option
                        Button {
                            layout.wrappedValue = option
                        } label: {
                            Image(systemName: option.icon)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isActive ? palette.accent : palette.ink60)
                                .frame(width: 28, height: 24)
                                .background(
                                    isActive ? palette.raised : palette.panel,
                                    in: RoundedRectangle(cornerRadius: 5)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(isActive ? palette.accent.opacity(0.5) : palette.border, lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .help(option.title)
                    }
                }
            }
            if layout.wrappedValue != .none, !accessibilityTrusted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.selection)
                    Text(L10n.t(.playLayoutHint))
                        .font(Theme.subFont)
                        .foregroundStyle(palette.ink60)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Button(action: onGrantAccess) {
                        Text(L10n.t(.playGrantAccess))
                            .font(Theme.subFont)
                            .foregroundStyle(palette.accent)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    // MARK: Shortcut

    /// Menu over the installed shortcuts plus a free-text field — the CLI
    /// list can lag behind a shortcut created a moment ago.
    private func shortcutPicker(_ name: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                if shortcuts.isEmpty {
                    Text("—")
                }
                ForEach(shortcuts, id: \.self) { shortcut in
                    Button(shortcut) {
                        name.wrappedValue = shortcut
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(name.wrappedValue.isEmpty ? L10n.t(.playChooseShortcut) : name.wrappedValue)
                        .font(Theme.bodyFont)
                        .foregroundStyle(name.wrappedValue.isEmpty ? palette.ink40 : palette.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.ink40)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            PaletteTextField(placeholder: L10n.t(.playShortcutName), text: name, palette: palette)
        }
    }

    // MARK: URLs

    private var urlsEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: urlsText)
                .font(Theme.bodyFont)
                .foregroundStyle(palette.ink)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(height: 84)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            if urlsText.wrappedValue.isEmpty {
                Text(L10n.t(.playURLsHint))
                    .font(Theme.bodyFont)
                    .foregroundStyle(palette.ink40)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Payload bindings

    private var bundleIDs: Binding<[String]> {
        Binding(
            get: {
                if case .openApps(_, let ids, _) = step { return ids }
                return []
            },
            set: { newValue in
                if case .openApps(let id, _, let layout) = step {
                    step = .openApps(id: id, bundleIDs: newValue, layout: layout)
                }
            }
        )
    }

    private var layout: Binding<WindowLayout> {
        Binding(
            get: {
                if case .openApps(_, _, let layout) = step { return layout }
                return .none
            },
            set: { newValue in
                if case .openApps(let id, let ids, _) = step {
                    step = .openApps(id: id, bundleIDs: ids, layout: newValue)
                }
            }
        )
    }

    private var shortcutName: Binding<String> {
        Binding(
            get: {
                if case .runShortcut(_, let name) = step { return name }
                return ""
            },
            set: { newValue in
                if case .runShortcut(let id, _) = step {
                    step = .runShortcut(id: id, name: newValue)
                }
            }
        )
    }

    private var focusShortcutName: Binding<String> {
        Binding(
            get: {
                if case .setFocus(_, let name) = step { return name }
                return ""
            },
            set: { newValue in
                if case .setFocus(let id, _) = step {
                    step = .setFocus(id: id, shortcutName: newValue)
                }
            }
        )
    }

    private var minutesText: Binding<String> {
        Binding(
            get: {
                if case .startTimer(_, let minutes) = step, minutes > 0 { return String(minutes) }
                return ""
            },
            set: { newValue in
                if case .startTimer(let id, _) = step {
                    step = .startTimer(id: id, minutes: Int(newValue.filter(\.isNumber)) ?? 0)
                }
            }
        )
    }

    /// Lines map straight to entries; empties survive while typing and
    /// are dropped on save.
    private var urlsText: Binding<String> {
        Binding(
            get: {
                if case .openURLs(_, let urls) = step { return urls.joined(separator: "\n") }
                return ""
            },
            set: { newValue in
                if case .openURLs(let id, _) = step {
                    step = .openURLs(id: id, urls: newValue.components(separatedBy: "\n"))
                }
            }
        )
    }
}

// MARK: - Shared controls

/// Plain text field in the settings "input box" look.
private struct PaletteTextField: View {
    let placeholder: String
    @Binding var text: String
    let palette: WindowPalette

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Theme.bodyFont)
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// Multi-select app picker: search, source filter chips, the list with
/// chosen apps floated to the top, and a bundle-ID escape hatch for
/// anything Spotlight cannot see.
private struct AppPickerView: View {
    let apps: [InstalledApp]
    @Binding var selected: [String]
    let palette: WindowPalette

    @State private var filter = ""
    @State private var manualBundleID = ""
    /// Empty means "no source filter" — show everything.
    @State private var sources: Set<AppSource> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink40)
                TextField(L10n.t(.playSearchApps), text: $filter)
                    .textFieldStyle(.plain)
                    .font(Theme.bodyFont)
                    .foregroundStyle(palette.ink)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            sourceChips
            if apps.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("…")
                        .font(Theme.subFont)
                        .foregroundStyle(palette.ink40)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filtered) { app in
                            row(app)
                        }
                    }
                    .padding(4)
                }
                .frame(height: 150)
                .background(palette.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("\(filtered.count) / \(apps.count) · " + L10n.f(.playSelectedCount, selected.count))
                    .font(Theme.subFont)
                    .foregroundStyle(palette.ink40)
            }
            HStack(spacing: 8) {
                TextField(L10n.t(.playAddBundleID), text: $manualBundleID)
                    .textFieldStyle(.plain)
                    .font(Theme.bodyFont)
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .onSubmit(addManual)
                Button(action: addManual) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 26, height: 26)
                        .background(palette.accentWash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .disabled(manualBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var sourceChips: some View {
        HStack(spacing: 6) {
            ForEach(AppSource.allCases) { source in
                let isOn = sources.contains(source)
                Button {
                    if isOn {
                        sources.remove(source)
                    } else {
                        sources.insert(source)
                    }
                } label: {
                    Text(source.title)
                        .font(Theme.captionFont)
                        .foregroundStyle(isOn ? palette.accent : palette.ink60)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(isOn ? palette.accentWash : palette.raised, in: Capsule())
                        .overlay(Capsule().stroke(isOn ? palette.accent.opacity(0.5) : Color.clear, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
            Spacer(minLength: 0)
        }
    }

    private var filtered: [InstalledApp] {
        let chosen = Set(selected)
        var matching = apps
        if !sources.isEmpty {
            matching = matching.filter { sources.contains($0.source) }
        }
        if !filter.isEmpty {
            matching = matching.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        }
        // Selected apps float to the top so choices stay visible.
        return matching.sorted {
            (chosen.contains($0.id) ? 0 : 1, $0.name) < (chosen.contains($1.id) ? 0 : 1, $1.name)
        }
    }

    private func row(_ app: InstalledApp) -> some View {
        let isSelected = selected.contains(app.id)
        return Button {
            if isSelected {
                selected.removeAll { $0 == app.id }
            } else {
                selected.append(app.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? palette.accent : palette.ink40)
                if let icon = AppVisuals.icon(for: app.id) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(app.name)
                    .font(Theme.bodyFont)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addManual() {
        let trimmed = manualBundleID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if !selected.contains(trimmed) {
            selected.append(trimmed)
        }
        manualBundleID = ""
    }
}

struct InstalledApp: Identifiable, Equatable, Sendable {
    let id: String // bundle ID
    let name: String
    let source: AppSource
}

/// Where an app lives — the noise filter: user-facing apps sit in
/// /Applications and ~/Applications, preinstalled and vendor bundles
/// elsewhere.
enum AppSource: String, CaseIterable, Identifiable, Sendable {
    case applications
    case user
    case system
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applications: "Applications"
        case .user: "~/Applications"
        case .system: "System"
        case .other: "Other"
        }
    }

    static func categorize(path: String, home: String) -> AppSource {
        if path.hasPrefix("\(home)/Applications/") { return .user }
        if path.hasPrefix("/Applications/") { return .applications }
        if path.hasPrefix("/System/") || path.hasPrefix("/Library/Apple/") { return .system }
        return .other
    }
}

/// Finds every installed application the way Launchpad does — via Spotlight —
/// with a directory scan as fallback for machines with indexing disabled.
enum AppCatalog {
    static func discover() async -> [InstalledApp] {
        var byBundleID: [String: (app: InstalledApp, path: String)] = [:]
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        func register(path: String) {
            guard path.hasSuffix(".app"),
                  !path.contains(".app/"),               // helpers inside bundles
                  !path.contains("/Library/Developer/"), // simulators, previews
                  !path.hasPrefix("/Volumes/")
            else { return }
            guard let bundle = Bundle(path: path), let bundleID = bundle.bundleIdentifier else { return }
            let name = FileManager.default.displayName(atPath: path)
                .replacingOccurrences(of: ".app", with: "")
            // Prefer the /Applications copy when duplicates exist.
            if let existing = byBundleID[bundleID],
               existing.path.hasPrefix("/Applications"), !path.hasPrefix("/Applications") {
                return
            }
            byBundleID[bundleID] = (
                InstalledApp(
                    id: bundleID,
                    name: name,
                    source: AppSource.categorize(path: path, home: home)
                ),
                path
            )
        }

        for path in await spotlightPaths() {
            register(path: path)
        }
        for path in directoryScanPaths() {
            register(path: path)
        }

        return byBundleID.values
            .map(\.app)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func spotlightPaths() async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
                process.arguments = ["kMDItemContentTypeTree == 'com.apple.application-bundle'"]
                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = Pipe()
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: [])
                    return
                }
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let paths = String(data: data, encoding: .utf8)?
                    .components(separatedBy: "\n")
                    .filter { !$0.isEmpty } ?? []
                continuation.resume(returning: paths)
            }
        }
    }

    /// One level deep over the standard locations — enough to catch
    /// /Applications subfolders and ~/Applications when Spotlight is off.
    private static func directoryScanPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "\(home)/Applications",
        ]
        var paths: [String] = []
        for root in roots {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
            for entry in entries {
                let full = "\(root)/\(entry)"
                if entry.hasSuffix(".app") {
                    paths.append(full)
                } else {
                    // Vendor subfolders like /Applications/Utilities.
                    let nested = (try? FileManager.default.contentsOfDirectory(atPath: full)) ?? []
                    paths.append(contentsOf: nested.filter { $0.hasSuffix(".app") }.map { "\(full)/\($0)" })
                }
            }
        }
        return paths
    }
}
