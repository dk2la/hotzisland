import SwiftUI

/// "Hotkeys" module: the shortcuts of the app being worked in — from its
/// menu bar, or from its key preset where the menus carry none (Resolve).
/// The app as a hero card (hold it, re-read its menus, import a preset),
/// pinned shortcuts first, then one grouped list per menu or preset
/// section; search and "add your own" at the bottom. Rows are for reading
/// only — hover to pin, right-click for tags.
struct AppShortcutsModuleView: View {
    var service: AppShortcutsService

    /// Whether this view instance holds a visibility claim on the service;
    /// appear/disappear can fire repeatedly during transitions.
    @State private var isObserving = false
    /// nil: the list. Otherwise the form for a new or an existing shortcut.
    @State private var editing: EditorTarget?
    /// The chosen file was not the app's key preset; shown for a moment.
    @State private var importFailed = false

    private enum EditorTarget: Identifiable {
        case new
        case existing(AppShortcut)

        var id: String {
            switch self {
            case .new: "new"
            case let .existing(shortcut): shortcut.id
            }
        }
    }

    var body: some View {
        Group {
            if let editing {
                ShortcutEditorView(service: service, original: original(of: editing)) {
                    self.editing = nil
                }
                .id(editing.id)
            } else {
                list
            }
        }
        .onAppear {
            guard !isObserving else { return }
            isObserving = true
            service.beginObserving()
        }
        .onDisappear {
            guard isObserving else { return }
            isObserving = false
            service.endObserving()
            service.cancelRecording()
        }
        // The form belongs to the app it was opened for.
        .onChange(of: service.target?.bundleID) {
            editing = nil
        }
    }

    private func original(of target: EditorTarget) -> AppShortcut? {
        if case let .existing(shortcut) = target { return shortcut }
        return nil
    }

    // MARK: - List

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let target = service.target {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        hero(target)
                        content
                    }
                }
                searchBar
            } else {
                EmptyStateZone(label: L10n.t(.keysNoApp), sublabel: L10n.t(.keysNoAppSub))
                    .frame(maxHeight: 100)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func hero(_ target: AppShortcutsService.TargetApp) -> some View {
        HeroCard {
            HStack(spacing: 12) {
                if let icon = target.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 36, height: 36)
                } else {
                    IconTile(systemName: "keyboard", size: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(heroCaption)
                        .heroCaption()
                    Text(target.name)
                        .font(Theme.heroFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer(minLength: 0)
                if service.supportsPresetImport {
                    presetMenu
                }
                ModuleButton(systemName: service.isHoldingApp ? "pin.fill" : "pin") {
                    service.toggleHold()
                }
                .help(L10n.t(service.isHoldingApp ? .keysFollowApp : .keysHoldApp))
                ModuleButton(
                    systemName: "arrow.clockwise",
                    enabled: service.isTrusted && service.isTargetRunning && !service.isReading
                ) {
                    service.refresh()
                }
                .help(L10n.t(.keysRefresh))
            }
            if importFailed {
                Text(L10n.t(.keysImportFailed))
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.critical)
                    .transition(.opacity)
            }
            if !service.isTrusted, service.presetShortcuts.isEmpty {
                Text(L10n.t(.keysAccessSub))
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ModuleButton(label: L10n.t(.obAllowAccess), kind: .accent) {
                    WindowLayoutService.requestAccess()
                }
            } else if service.snapshot == nil, !service.isTargetRunning, service.presetShortcuts.isEmpty {
                Text(L10n.t(.keysNotRunning))
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var heroCaption: String {
        if service.isReading { return L10n.t(.keysReading) }
        let count = service.menuShortcuts.count + service.presetShortcuts.count + service.customShortcuts.count
        guard service.snapshot != nil || count > 0 else { return L10n.t(.modKeys) }
        let caption = L10n.f(.keysCount, count)
        guard service.supportsPresetImport else { return caption }
        return caption + " · " + L10n.t(service.hasImportedPreset ? .keysFromFile : .keysBuiltInSet)
    }

    /// Import the app's exported key preset, or go back to the built-in set.
    private var presetMenu: some View {
        Menu {
            Button(L10n.t(.keysImport)) {
                let imported = service.importPreset()
                withAnimation(.easeOut(duration: 0.15)) { importFailed = !imported }
                if !imported {
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(.easeOut(duration: 0.15)) { importFailed = false }
                    }
                }
            }
            if service.hasImportedPreset {
                Button(L10n.t(.keysUseBuiltIn)) {
                    service.useBuiltInPreset()
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.raisedFill))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        let query = service.query
        let pinned = service.pinnedShortcuts.filter { service.matches($0, query: query) }
        let pinnedIDs = Set(pinned.map(\.id))
        let custom = service.customShortcuts.filter { !pinnedIDs.contains($0.id) && service.matches($0, query: query) }
        let menus = Self.groupedByMenu(
            (service.presetShortcuts + service.menuShortcuts)
                .filter { !pinnedIDs.contains($0.id) && service.matches($0, query: query) }
        )

        if pinned.isEmpty, custom.isEmpty, menus.isEmpty {
            emptyState(searching: !query.trimmingCharacters(in: .whitespaces).isEmpty)
        } else {
            LazyVStack(alignment: .leading, spacing: 18) {
                if !pinned.isEmpty {
                    section(L10n.t(.keysPinned), pinned)
                }
                if !custom.isEmpty {
                    section(L10n.t(.keysMine), custom)
                }
                ForEach(menus, id: \.menu) { group in
                    section(group.menu, group.shortcuts)
                }
            }
        }
    }

    @ViewBuilder
    private func emptyState(searching: Bool) -> some View {
        if searching {
            EmptyStateZone(label: L10n.t(.mailNoResults))
                .frame(height: 80)
        } else if service.snapshot != nil || service.supportsPresetImport {
            VStack(spacing: 12) {
                EmptyStateZone(label: L10n.t(.keysNone), sublabel: L10n.t(.keysNoneSub))
                    .frame(height: 80)
                ModuleButton(label: L10n.t(.keysAddOwn), systemName: "plus", kind: .light) {
                    editing = .new
                }
            }
            .frame(maxWidth: .infinity)
        }
        // Still reading, or no access yet: the hero card says so.
    }

    private func section(_ title: String, _ shortcuts: [AppShortcut]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title, trailing: "\(shortcuts.count)")
            GroupedCard {
                ForEach(Array(shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                    ShortcutRow(
                        shortcut: shortcut,
                        tags: service.tags(of: shortcut),
                        isPinned: service.isPinned(shortcut),
                        isLast: index == shortcuts.count - 1,
                        onPin: { service.togglePin(shortcut) },
                        onEdit: { editing = .existing(shortcut) },
                        onDelete: shortcut.isCustom ? { service.deleteCustom(shortcut) } : nil
                    )
                }
            }
        }
    }

    /// Menu shortcuts by top-level menu, in menu bar order.
    private static func groupedByMenu(_ shortcuts: [AppShortcut]) -> [(menu: String, shortcuts: [AppShortcut])] {
        var groups: [(menu: String, shortcuts: [AppShortcut])] = []
        for shortcut in shortcuts {
            let menu = shortcut.menuPath.first ?? ""
            if let index = groups.firstIndex(where: { $0.menu == menu }) {
                groups[index].shortcuts.append(shortcut)
            } else {
                groups.append((menu, [shortcut]))
            }
        }
        return groups
    }

    private var searchBar: some View {
        ComposerBar {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 30, height: 30)
            TextField(L10n.t(.keysSearch), text: Bindable(service).query)
                .textFieldStyle(.plain)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textPrimary)
            if !service.query.isEmpty {
                ModuleButton(systemName: "xmark", height: 30) {
                    service.query = ""
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            ModuleButton(systemName: "plus", height: 30) {
                editing = .new
            }
            .help(L10n.t(.keysNew))
        }
        .animation(Theme.stateSpring, value: service.query.isEmpty)
    }
}

// MARK: - Row

/// One shortcut: title, the submenu path and tags underneath, key caps on
/// the right. The pin shows on hover, and stays while pinned.
private struct ShortcutRow: View {
    let shortcut: AppShortcut
    let tags: [String]
    let isPinned: Bool
    let isLast: Bool
    let onPin: () -> Void
    let onEdit: () -> Void
    let onDelete: (() -> Void)?

    @State private var hovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.title)
                    .font(Theme.bodyFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.textPrimary)
                if let detail {
                    Text(detail)
                        .font(Theme.captionFont)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
            if hovered || isPinned {
                Button(action: onPin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isPinned ? Theme.accent : Theme.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .help(L10n.t(isPinned ? .keysUnpin : .keysPin))
                .transition(.opacity)
            }
            ShortcutKeys(keys: shortcut.keys)
        }
        .groupedRow(isLast: isLast)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .contextMenu {
            Button(L10n.t(isPinned ? .keysUnpin : .keysPin), action: onPin)
            Button(L10n.t(.keysEditTags), action: onEdit)
            if let onDelete {
                Divider()
                Button(L10n.t(.calDelete), role: .destructive, action: onDelete)
            }
        }
    }

    /// "Export › Movie" under a nested item, then "#crop #trim".
    private var detail: String? {
        let submenus = shortcut.menuPath.dropFirst().joined(separator: AppShortcut.pathSeparator)
        let tagLine = tags.map { "#\($0)" }.joined(separator: " ")
        let parts = [submenus, tagLine].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Key caps on raised glass: ⌃ ⌥ ⇧ ⌘ then the key, one cap each.
struct ShortcutKeys: View {
    let keys: KeyStroke

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.keyCaps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(Theme.subFont)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.raisedFill)
                    )
            }
        }
        .fixedSize()
    }
}

// MARK: - Editor

/// The form for one shortcut. A new or custom shortcut edits keys, name and
/// tags; a menu shortcut only its tags — its keys belong to the app.
private struct ShortcutEditorView: View {
    var service: AppShortcutsService
    let original: AppShortcut?
    let onClose: () -> Void

    @State private var keys: KeyStroke?
    @State private var title = ""
    @State private var tagsText = ""
    @FocusState private var titleFocused: Bool

    private var isMenuItem: Bool { original.map { !$0.isCustom } ?? false }

    private var canSave: Bool {
        isMenuItem || (keys != nil && !title.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: original?.title ?? L10n.t(.keysNew))
                    GroupedCard {
                        field(L10n.t(.keysKeys), isLast: false) { keysControl }
                        field(L10n.t(.keysName), isLast: false) {
                            if isMenuItem {
                                Text(original?.title ?? "")
                                    .font(Theme.bodyFont)
                                    .lineLimit(1)
                                    .foregroundStyle(Theme.textSecondary)
                            } else {
                                TextField("", text: $title)
                                    .textFieldStyle(.plain)
                                    .font(Theme.bodyFont)
                                    .foregroundStyle(Theme.textPrimary)
                                    .focused($titleFocused)
                            }
                        }
                        field(L10n.t(.keysTags), isLast: true) {
                            TextField(L10n.t(.keysTagsHint), text: $tagsText)
                                .textFieldStyle(.plain)
                                .font(Theme.bodyFont)
                                .foregroundStyle(Theme.textPrimary)
                                .onSubmit(save)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ModuleButton(label: L10n.t(.mailCancel)) {
                    service.cancelRecording()
                    onClose()
                }
                ModuleButton(label: L10n.t(.calSave), kind: .accent, enabled: canSave, action: save)
            }
        }
        .onAppear {
            keys = original?.keys
            title = original?.title ?? ""
            tagsText = original.map { service.tags(of: $0).joined(separator: ", ") } ?? ""
            if original == nil { titleFocused = true }
        }
        .onDisappear { service.cancelRecording() }
    }

    private func field<Content: View>(_ label: String, isLast: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(Theme.subFont)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 64, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .groupedRow(isLast: isLast)
    }

    @ViewBuilder
    private var keysControl: some View {
        if isMenuItem, let keys {
            ShortcutKeys(keys: keys)
        } else {
            Button {
                if service.isRecording {
                    service.cancelRecording()
                } else {
                    service.startRecording { keys = $0 }
                }
            } label: {
                Group {
                    if service.isRecording {
                        HStack(spacing: 7) {
                            BlinkingDot(color: Theme.accent, size: 5)
                            Text(L10n.t(.hkRecord))
                                .font(Theme.subFont)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.accentWash)
                        )
                    } else if let keys {
                        ShortcutKeys(keys: keys)
                    } else {
                        Text(L10n.t(.hkRecord))
                            .font(Theme.subFont)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.raisedFill)
                            )
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func save() {
        guard canSave else { return }
        service.cancelRecording()
        var shortcut = original
        if !isMenuItem, let keys {
            let name = title.trimmingCharacters(in: .whitespaces)
            if var existing = shortcut {
                existing.title = name
                existing.keys = keys
                shortcut = existing
            } else {
                shortcut = .custom(title: name, keys: keys)
            }
            if let shortcut { service.saveCustom(shortcut) }
        }
        if let shortcut {
            service.setTags(Self.parseTags(tagsText), of: shortcut)
        }
        onClose()
    }

    /// "crop, Trim , crop" → ["crop", "Trim"].
    private static func parseTags(_ text: String) -> [String] {
        var seen: Set<String> = []
        return text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
