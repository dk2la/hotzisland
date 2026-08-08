import AppKit
import SwiftUI

/// Editor sheet for a single playbook: name, icon, apps to open,
/// close-others toggle, Shortcuts bridge and timer.
struct PlaybookEditorView: View {
    var store: PlaybookStore
    /// nil means "create new".
    var existing: Playbook?
    let onDone: () -> Void

    @State private var draft: Playbook
    @State private var apps: [InstalledApp] = []
    @State private var appFilter = ""
    @State private var manualBundleID = ""
    /// Empty means "no source filter" — show everything.
    @State private var selectedSources: Set<AppSource> = []
    @FocusState private var searchFocused: Bool

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
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    Picker("Icon", selection: $draft.icon) {
                        ForEach(Self.icons, id: \.self) { icon in
                            Image(systemName: icon).tag(icon)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Apps to open") {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search all applications…", text: $appFilter)
                            .textFieldStyle(.plain)
                            .focused($searchFocused)
                    }
                    sourceFilterChips
                    if apps.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Scanning applications…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                    } else {
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 1) {
                                ForEach(filteredApps) { app in
                                    appRow(app)
                                }
                            }
                        }
                        .frame(height: 220)
                        Text("\(filteredApps.count) of \(apps.count) apps · \(draft.openBundleIDs.count) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // Escape hatch for anything Spotlight cannot see.
                    HStack {
                        TextField("Add by bundle ID (e.g. com.figma.Desktop)", text: $manualBundleID)
                        Button("Add") {
                            let trimmed = manualBundleID.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            if !draft.openBundleIDs.contains(trimmed) {
                                draft.openBundleIDs.append(trimmed)
                            }
                            manualBundleID = ""
                        }
                        .disabled(manualBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section {
                    Toggle("Close other apps", isOn: $draft.closeOthers)
                    Text("Politely quits every open app that is not part of this playbook. Apps with unsaved work will ask first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Extras") {
                    TextField("Shortcuts shortcut (e.g. Work Focus)", text: shortcutBinding)
                    TextField("Start timer (minutes)", text: timerBinding)
                }
            }
            .formStyle(.grouped)

            HStack {
                if existing != nil {
                    Button(role: .destructive) {
                        if let existing { store.remove(existing) }
                        onDone()
                    } label: {
                        Text("Delete")
                    }
                }
                Spacer()
                Button("Cancel") { onDone() }
                Button("Save") {
                    if existing == nil {
                        store.add(draft)
                    } else {
                        store.update(draft)
                    }
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 460, height: 620)
        .task {
            apps = await AppCatalog.discover()
            searchFocused = true
        }
    }

    private var sourceFilterChips: some View {
        HStack(spacing: 6) {
            ForEach(AppSource.allCases) { source in
                let isOn = selectedSources.contains(source)
                Button {
                    if isOn {
                        selectedSources.remove(source)
                    } else {
                        selectedSources.insert(source)
                    }
                } label: {
                    Text(source.title)
                        .font(.caption)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(
                            isOn ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(
                            isOn ? Color.accentColor : Color.clear, lineWidth: 1
                        ))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            if !selectedSources.isEmpty {
                Button("All") { selectedSources.removeAll() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var filteredApps: [InstalledApp] {
        let selected = Set(draft.openBundleIDs)
        var matching = apps
        if !selectedSources.isEmpty {
            matching = matching.filter { selectedSources.contains($0.source) }
        }
        if !appFilter.isEmpty {
            matching = matching.filter { $0.name.localizedCaseInsensitiveContains(appFilter) }
        }
        // Selected apps float to the top so choices stay visible.
        return matching.sorted {
            (selected.contains($0.id) ? 0 : 1, $0.name) < (selected.contains($1.id) ? 0 : 1, $1.name)
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        let isSelected = draft.openBundleIDs.contains(app.id)
        return Button {
            if isSelected {
                draft.openBundleIDs.removeAll { $0 == app.id }
            } else {
                draft.openBundleIDs.append(app.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(app.name)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var shortcutBinding: Binding<String> {
        Binding(
            get: { draft.shortcutName ?? "" },
            set: { draft.shortcutName = $0.isEmpty ? nil : $0 }
        )
    }

    private var timerBinding: Binding<String> {
        Binding(
            get: { draft.timerMinutes.map(String.init) ?? "" },
            set: { draft.timerMinutes = Int($0).flatMap { $0 > 0 ? $0 : nil } }
        )
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
