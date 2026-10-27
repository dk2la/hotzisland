import AppKit
import UniformTypeIdentifiers
import Carbon.HIToolbox
import Observation
import OSLog

/// Shortcuts of the app being worked in, for the "Hotkeys" module. Follows
/// the frontmost app (or one the user holds), reads its menu bar once per
/// app version and keeps that on disk; pins, tags and the user's own
/// shortcuts live beside it, per bundle id.
///
/// Watching the frontmost app is a workspace notification — free. The menu
/// read is the only real cost, so it runs only while the module is on
/// screen and only when nothing is cached.
@MainActor
@Observable
final class AppShortcutsService {
    struct TargetApp {
        let bundleID: String
        let name: String
        let icon: NSImage?
    }

    private(set) var target: TargetApp?
    /// The user holds this app instead of following the frontmost one.
    private(set) var heldBundleID: String?
    private(set) var isTrusted = WindowLayoutService.isTrusted
    /// Bundle id whose menu is being read right now.
    private(set) var readingBundleID: String?
    private(set) var snapshots: [String: MenuSnapshot] = [:]
    private(set) var prefs: [String: AppShortcutPrefs] = [:]
    /// The read for the target failed (it hung or quit mid-read).
    private(set) var lastReadFailed = false
    var query = ""
    private(set) var isRecording = false

    @ObservationIgnored private var lastFrontmost: TargetApp?
    @ObservationIgnored private var observers = 0
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var onRecorded: ((KeyStroke) -> Void)?
    /// Parsed once per app — the bundled files never change at run time.
    @ObservationIgnored private var builtInPresets: [String: [AppShortcut]] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "hotkeys")

    @ObservationIgnored private static let heldAppKey = "hotkeys.heldApp"
    @ObservationIgnored private static let folder: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("HotzIsland", isDirectory: true)
    }()
    /// The user's data — pins, tags, own shortcuts.
    @ObservationIgnored private static let prefsURL = folder.appendingPathComponent("hotkeys.json")
    /// Disposable: rebuilt from the apps' menus whenever it is missing.
    @ObservationIgnored private static let menusURL = folder.appendingPathComponent("hotkeys-menus.json")

    init() {
        prefs = Self.load([String: AppShortcutPrefs].self, from: Self.prefsURL) ?? [:]
        snapshots = Self.load([String: MenuSnapshot].self, from: Self.menusURL) ?? [:]
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            lastFrontmost = Self.targetApp(for: frontmost)
        }
        heldBundleID = UserDefaults.standard.string(forKey: Self.heldAppKey)
        updateTarget()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.appActivated(app)
            }
        }
    }

    // MARK: - Visibility

    /// The module came on screen: re-check access, read what is missing.
    func beginObserving() {
        observers += 1
        isTrusted = WindowLayoutService.isTrusted
        readIfNeeded()
    }

    func endObserving() {
        observers = max(0, observers - 1)
    }

    private func appActivated(_ app: NSRunningApplication?) {
        // Coming back from System Settings is an activation too — the
        // moment access may have been granted.
        isTrusted = WindowLayoutService.isTrusted
        if let app, let next = Self.targetApp(for: app) {
            lastFrontmost = next
        }
        updateTarget()
        readIfNeeded()
    }

    // MARK: - Target app

    var isHoldingApp: Bool { heldBundleID != nil }

    func toggleHold() {
        heldBundleID = heldBundleID == nil ? target?.bundleID : nil
        UserDefaults.standard.set(heldBundleID, forKey: Self.heldAppKey)
        updateTarget()
        readIfNeeded()
    }

    private func updateTarget() {
        if let heldBundleID {
            if target?.bundleID != heldBundleID {
                target = Self.targetApp(bundleID: heldBundleID)
            }
        } else if target?.bundleID != lastFrontmost?.bundleID {
            target = lastFrontmost
        }
    }

    /// Our own panel taking focus must not swap the list away.
    private static func targetApp(for app: NSRunningApplication) -> TargetApp? {
        guard let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier else { return nil }
        return TargetApp(bundleID: bundleID, name: app.localizedName ?? bundleID, icon: app.icon)
    }

    /// A held app may not be running: name and icon come from its bundle.
    private static func targetApp(bundleID: String) -> TargetApp {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let app = targetApp(for: running) {
            return app
        }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
        return TargetApp(
            bundleID: bundleID,
            name: name ?? bundleID,
            icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) }
        )
    }

    // MARK: - Reading

    var isReading: Bool { readingBundleID != nil && readingBundleID == target?.bundleID }

    var isTargetRunning: Bool {
        guard let target else { return false }
        return Self.runningApp(target.bundleID) != nil
    }

    /// Re-reads the target's menus even when cached — after the user rebinds
    /// keys in the app.
    func refresh() {
        readIfNeeded(force: true)
    }

    private func readIfNeeded(force: Bool = false) {
        guard observers > 0, isTrusted, readingBundleID == nil,
              let target, let app = Self.runningApp(target.bundleID) else { return }
        let version = Self.version(of: app)
        if !force, let snapshot = snapshots[target.bundleID], snapshot.appVersion == version { return }

        let bundleID = target.bundleID
        let pid = app.processIdentifier
        readingBundleID = bundleID
        lastReadFailed = false
        Task {
            let started = Date()
            let shortcuts = await Task.detached(priority: .utility) {
                MenuShortcutReader.read(pid: pid)
            }.value
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            readingBundleID = nil
            if let shortcuts {
                log.info("read \(bundleID, privacy: .public): \(shortcuts.count, privacy: .public) shortcuts in \(elapsed, privacy: .public) ms")
                snapshots[bundleID] = MenuSnapshot(appVersion: version, readAt: Date(), shortcuts: shortcuts)
                Self.save(snapshots, to: Self.menusURL)
            } else {
                log.notice("read \(bundleID, privacy: .public) failed after \(elapsed, privacy: .public) ms")
                if bundleID == self.target?.bundleID { lastReadFailed = true }
            }
            // The user may have switched apps while this one was read.
            if bundleID != self.target?.bundleID { readIfNeeded() }
        }
    }

    private static func runningApp(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }
    }

    /// "19.1.3 (5)" — menus change between builds, so both parts count.
    private static func version(of app: NSRunningApplication) -> String {
        let info = app.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary } ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        return "\(short) (\(build))"
    }

    // MARK: - Shortcuts of the target

    var snapshot: MenuSnapshot? {
        target.flatMap { snapshots[$0.bundleID] }
    }

    private var targetPrefs: AppShortcutPrefs {
        target.flatMap { prefs[$0.bundleID] } ?? AppShortcutPrefs()
    }

    var customShortcuts: [AppShortcut] { targetPrefs.custom }

    /// The menu bar's shortcuts, minus those the app's preset already lists
    /// (Resolve's app menu repeats ⌘, and ⌘Q).
    var menuShortcuts: [AppShortcut] {
        let shortcuts = snapshot?.shortcuts ?? []
        let presetKeys = Set(presetShortcuts.map(\.keys))
        guard !presetKeys.isEmpty else { return shortcuts }
        return shortcuts.filter { !presetKeys.contains($0.keys) }
    }

    /// The app has a key preset format: import is offered.
    var supportsPresetImport: Bool { targetPreset != nil }
    var hasImportedPreset: Bool { targetPrefs.imported != nil }

    /// The imported preset, else the built-in default set.
    var presetShortcuts: [AppShortcut] {
        if let imported = targetPrefs.imported { return imported }
        guard let target, let preset = targetPreset else { return [] }
        if let cached = builtInPresets[target.bundleID] { return cached }
        let shortcuts = preset.builtIn
        builtInPresets[target.bundleID] = shortcuts
        return shortcuts
    }

    /// Pinned shortcuts in pin order; pins whose item is gone are skipped.
    var pinnedShortcuts: [AppShortcut] {
        let all = Dictionary((customShortcuts + presetShortcuts + menuShortcuts).map { ($0.id, $0) }) { first, _ in first }
        return targetPrefs.pinned.compactMap { all[$0] }
    }

    private var targetPreset: KeyPreset? {
        target.flatMap { KeyPreset.forApp($0.bundleID) }
    }

    /// Asks for the app's exported preset and keeps it in place of the
    /// built-in set. False when the file is not that app's export.
    @discardableResult
    func importPreset() -> Bool {
        guard let preset = targetPreset else { return false }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return true }
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let shortcuts = preset.parse(text) else {
            log.notice("import \(url.lastPathComponent, privacy: .public): not a key preset")
            return false
        }
        log.info("imported \(shortcuts.count, privacy: .public) shortcuts from \(url.lastPathComponent, privacy: .public)")
        updatePrefs { $0.imported = shortcuts }
        return true
    }

    /// Drops the imported preset; the built-in set shows again.
    func useBuiltInPreset() {
        updatePrefs { $0.imported = nil }
    }

    func isPinned(_ shortcut: AppShortcut) -> Bool {
        targetPrefs.pinned.contains(shortcut.id)
    }

    func tags(of shortcut: AppShortcut) -> [String] {
        targetPrefs.tags[shortcut.id] ?? []
    }

    /// Title, menu path and tags, ignoring case and accents.
    func matches(_ shortcut: AppShortcut, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return shortcut.title.localizedStandardContains(query)
            || shortcut.menuPath.contains { $0.localizedStandardContains(query) }
            || tags(of: shortcut).contains { $0.localizedStandardContains(query) }
    }

    func togglePin(_ shortcut: AppShortcut) {
        updatePrefs { prefs in
            if let index = prefs.pinned.firstIndex(of: shortcut.id) {
                prefs.pinned.remove(at: index)
            } else {
                prefs.pinned.append(shortcut.id)
            }
        }
    }

    func setTags(_ tags: [String], of shortcut: AppShortcut) {
        updatePrefs { prefs in
            prefs.tags[shortcut.id] = tags.isEmpty ? nil : tags
        }
    }

    /// Adds a new custom shortcut, or replaces one with the same id.
    func saveCustom(_ shortcut: AppShortcut) {
        updatePrefs { prefs in
            if let index = prefs.custom.firstIndex(where: { $0.id == shortcut.id }) {
                prefs.custom[index] = shortcut
            } else {
                prefs.custom.append(shortcut)
            }
        }
    }

    func deleteCustom(_ shortcut: AppShortcut) {
        updatePrefs { prefs in
            prefs.custom.removeAll { $0.id == shortcut.id }
            prefs.pinned.removeAll { $0 == shortcut.id }
            prefs.tags[shortcut.id] = nil
        }
    }

    private func updatePrefs(_ change: (inout AppShortcutPrefs) -> Void) {
        guard let bundleID = target?.bundleID else { return }
        var current = prefs[bundleID] ?? AppShortcutPrefs()
        change(&current)
        prefs[bundleID] = current.isEmpty ? nil : current
        Self.save(prefs, to: Self.prefsURL)
    }

    // MARK: - Recording

    /// Captures the next key press in our panel as a shortcut — any key, with
    /// or without modifiers, since app shortcuts are often bare letters.
    /// Esc alone cancels.
    func startRecording(_ completion: @escaping (KeyStroke) -> Void) {
        cancelRecording()
        isRecording = true
        onRecorded = completion
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            MainActor.assumeIsolated {
                self?.capture(keyCode: keyCode, flags: flags)
            }
            return nil
        }
    }

    func cancelRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        onRecorded = nil
        isRecording = false
    }

    private func capture(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard let combo = KeyCombo(keyCode: keyCode, flags: flags) else { return }
        let completion = onRecorded
        cancelRecording()
        if Int(combo.keyCode) == kVK_Escape, combo.modifiers == 0 { return }
        completion?(KeyStroke(modifiers: combo.modifiers, keyCode: combo.keyCode))
    }

    // MARK: - Persistence

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            Logger(subsystem: "com.dk2la.hotzisland", category: "hotkeys")
                .error("failed to save \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
        }
    }
}
