import Foundation
import Observation
import OSLog
import ServiceManagement

/// Capsule shell appearance.
enum CapsuleTheme: String {
    case stealth
    case glass
    case glow
}

/// What the capsule does when nothing demands attention.
enum IdleMode: String {
    /// Always shrink to the bare housing.
    case invisible
    /// Show compact indicators (playing track, running timer).
    case compact
}

extension Notification.Name {
    /// Posted by widget UI that wants the settings capsule opened; the
    /// AppDelegate observes it.
    static let pocketOpenSettings = Notification.Name("pocketOpenSettings")
    /// Posted with `userInfo["tab"]` (a ModuleTab raw value) to open that
    /// module in the widget — e.g. the assistant handing a form to the
    /// calendar.
    static let pocketShowModule = Notification.Name("pocketShowModule")
    /// Posted by UI that wants the welcome tour on the capsule (settings,
    /// context menus); the AppDelegate observes it.
    static let pocketOpenOnboarding = Notification.Name("pocketOpenOnboarding")
}

/// Asks the AppDelegate for the settings capsule, optionally on a page.
@MainActor
func requestSettings(page: SettingsView.Page? = nil) {
    NotificationCenter.default.post(
        name: .pocketOpenSettings,
        object: nil,
        userInfo: page.map { ["page": $0.rawValue] }
    )
}

/// Asks the AppDelegate for the welcome tour, from its first page.
@MainActor
func requestOnboarding() {
    NotificationCenter.default.post(name: .pocketOpenOnboarding, object: nil)
}

/// User preferences, persisted to UserDefaults.
@MainActor
@Observable
final class AppSettings {
    var theme: CapsuleTheme {
        didSet { persist(theme.rawValue, Self.themeKey, log: "theme") }
    }

    var idleMode: IdleMode {
        didSet { persist(idleMode.rawValue, Self.idleKey, log: "idleMode") }
    }

    /// Widget glass appearance (the capsule is always dark glass).
    var glassAppearance: GlassAppearance {
        didSet { persist(glassAppearance.rawValue, Self.glassAppearanceKey, log: "glassAppearance") }
    }

    /// Interface language — translates the widget, capsule and settings.
    var language: AppLanguage {
        didSet {
            L10n.shared.language = language
            persist(language.rawValue, Self.languageKey, log: "language")
        }
    }

    /// Edge the widget strip is docked to.
    private(set) var widgetEdge: WidgetEdge {
        didSet { persist(widgetEdge.rawValue, Self.widgetEdgeKey) }
    }

    /// Normalized 0…1 position of the strip's center along its edge.
    private(set) var widgetOffset: Double {
        didSet { persist(widgetOffset, Self.widgetOffsetKey) }
    }

    /// Clicking anywhere outside the widget closes the open panel. Off =
    /// the panel stays pinned until closed explicitly. ⌃⌥P flips it.
    var closeOnOutsideClick: Bool {
        didSet { persist(closeOnOutsideClick, Self.outsideClickKey, log: "closeOnOutsideClick") }
    }

    /// Widget rolled up to its grip plus the first module button (⌃⌥H).
    /// Persisted so a restart brings the widget back the way it was left.
    var widgetMinimized: Bool {
        didSet { persist(widgetMinimized, Self.widgetMinimizedKey, log: "widgetMinimized") }
    }

    /// The welcome tour opens on the capsule at every launch until switched
    /// off — from the tour's own footer or Settings → General.
    var showOnboardingAtLaunch: Bool {
        didSet { persist(showOnboardingAtLaunch, Self.onboardingAtLaunchKey, log: "showOnboardingAtLaunch") }
    }

    /// Size of the widget-mode panel, each axis dragged by its own grip.
    /// Separate from the capsule's `expandedPanelSize` — the two surfaces
    /// have different geometry.
    private(set) var widgetPanelWidth: CGFloat {
        didSet { persist(Double(widgetPanelWidth), Self.widgetPanelWidthKey) }
    }

    private(set) var widgetPanelHeight: CGFloat {
        didSet { persist(Double(widgetPanelHeight), Self.widgetPanelHeightKey) }
    }

    /// User-chosen size of the expanded panel (dragged by the corner grip).
    private(set) var expandedPanelSize: CGSize {
        didSet {
            defaults.set(Double(expandedPanelSize.width), forKey: Self.panelWidthKey)
            persist(Double(expandedPanelSize.height), Self.panelHeightKey)
        }
    }

    private(set) var enabledTabs: Set<ModuleTab> {
        didSet { persist(enabledTabs.map(\.rawValue).sorted(), Self.tabsKey) }
    }

    /// User-arranged channel order (Settings → Modules).
    private(set) var tabOrder: [ModuleTab] {
        didSet { persist(tabOrder.map(\.rawValue), Self.tabOrderKey) }
    }

    /// Launch-at-login through SMAppService; mirrored here for observation.
    private(set) var launchAtLogin: Bool

    /// Channels in user order, disabled ones filtered out.
    var orderedEnabledTabs: [ModuleTab] {
        tabOrder.filter { enabledTabs.contains($0) }
    }

    /// Both window controllers react to changes — the capsule re-evaluates its
    /// idle state, the widget re-derives its layout. Handlers are append-only.
    @ObservationIgnored private var changeHandlers: [() -> Void] = []

    func addChangeHandler(_ handler: @escaping () -> Void) {
        changeHandlers.append(handler)
    }

    /// The one write path of every persisted property.
    private func persist(_ value: Any, _ key: String, log name: String? = nil) {
        defaults.set(value, forKey: key)
        if let name {
            log.info("\(name, privacy: .public) -> \(String(describing: value), privacy: .public)")
        }
        for handler in changeHandlers {
            handler()
        }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.pocket", category: "settings")
    @ObservationIgnored private static let themeKey = "settings.theme"
    @ObservationIgnored private static let idleKey = "settings.idleMode"
    // v6: bumped when the hotkeys tab shipped (v5 = assistant, v4 = email,
    // v3 = notes, v2 = playbooks) — a stored older set would silently hide
    // new tabs, since "missing" is indistinguishable from "disabled by the user".
    @ObservationIgnored private static let tabsKey = "settings.enabledTabs.v6"
    /// (legacy key, tabs to surface when migrating from it)
    @ObservationIgnored private static let legacyTabsKeys: [(String, Set<ModuleTab>)] = [
        ("settings.enabledTabs.v5", [.hotkeys]),
        ("settings.enabledTabs.v4", [.assistant, .hotkeys]),
        ("settings.enabledTabs.v3", [.email, .assistant, .hotkeys]),
        ("settings.enabledTabs.v2", [.notes, .email, .assistant, .hotkeys]),
    ]
    @ObservationIgnored private static let panelWidthKey = "settings.panelWidth"
    @ObservationIgnored private static let panelHeightKey = "settings.panelHeight"
    @ObservationIgnored private static let tabOrderKey = "settings.tabOrder"
    @ObservationIgnored private static let glassAppearanceKey = "settings.glassAppearance"
    @ObservationIgnored private static let languageKey = "settings.language"
    @ObservationIgnored private static let widgetEdgeKey = "settings.widgetEdge"
    @ObservationIgnored private static let widgetOffsetKey = "settings.widgetOffset"
    @ObservationIgnored private static let outsideClickKey = "settings.closeOnOutsideClick"
    @ObservationIgnored private static let widgetMinimizedKey = "settings.widgetMinimized"
    @ObservationIgnored private static let onboardingAtLaunchKey = "settings.showOnboardingAtLaunch"
    @ObservationIgnored private static let widgetPanelWidthKey = "settings.widgetPanelWidth"
    @ObservationIgnored private static let widgetPanelHeightKey = "settings.widgetPanelHeight"

    init() {
        let defaults = UserDefaults.standard
        let storedWidth = defaults.double(forKey: Self.panelWidthKey)
        let storedHeight = defaults.double(forKey: Self.panelHeightKey)
        expandedPanelSize = Self.clampPanelSize(CGSize(
            width: storedWidth > 0 ? storedWidth : CapsuleMetrics.expandedMinSize.width,
            height: storedHeight > 0 ? storedHeight : CapsuleMetrics.expandedMinSize.height
        ))
        let storedPanelWidth = defaults.double(forKey: Self.widgetPanelWidthKey)
        widgetPanelWidth = Self.clampWidgetPanelWidth(
            storedPanelWidth > 0 ? storedPanelWidth : WidgetMetrics.panelDefaultWidth
        )
        let storedPanelHeight = defaults.double(forKey: Self.widgetPanelHeightKey)
        widgetPanelHeight = Self.clampWidgetPanelHeight(
            storedPanelHeight > 0 ? storedPanelHeight : WidgetMetrics.panelDefaultHeight
        )
        theme = defaults.string(forKey: Self.themeKey)
            .flatMap(CapsuleTheme.init(rawValue:)) ?? .stealth
        idleMode = defaults.string(forKey: Self.idleKey)
            .flatMap(IdleMode.init(rawValue:)) ?? .compact
        glassAppearance = defaults.string(forKey: Self.glassAppearanceKey)
            .flatMap(GlassAppearance.init(rawValue:)) ?? .dark
        language = defaults.string(forKey: Self.languageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        widgetEdge = defaults.string(forKey: Self.widgetEdgeKey)
            .flatMap(WidgetEdge.init(rawValue:)) ?? .right
        let storedOffset = defaults.object(forKey: Self.widgetOffsetKey) as? Double
        widgetOffset = min(max(storedOffset ?? 0.5, 0), 1)
        // Absent key = default ON: auto-close is the expected light behaviour.
        closeOnOutsideClick = (defaults.object(forKey: Self.outsideClickKey) as? Bool) ?? true
        widgetMinimized = defaults.bool(forKey: Self.widgetMinimizedKey)
        // Absent key = on: the tour shows until the user turns it off.
        showOnboardingAtLaunch = (defaults.object(forKey: Self.onboardingAtLaunchKey) as? Bool) ?? true
        // Coming-soon modules stay off until their services land.
        let defaultEnabled = Set(ModuleTab.allCases).subtracting(ModuleTab.comingSoon)
        if let stored = defaults.stringArray(forKey: Self.tabsKey) {
            let tabs = Set(stored.compactMap(ModuleTab.init(rawValue:)))
            enabledTabs = tabs.isEmpty ? defaultEnabled : tabs
        } else if let (legacy, extras) = Self.legacyTabsKeys
            .compactMap({ key, extras in
                defaults.stringArray(forKey: key).map { ($0, extras) }
            })
            .first {
            // Migration: keep the user's choices, surface freshly shipped
            // tabs they could not have known about.
            let tabs = Set(legacy.compactMap(ModuleTab.init(rawValue:))).union(extras)
            enabledTabs = tabs.isEmpty ? defaultEnabled : tabs
        } else {
            enabledTabs = defaultEnabled
        }
        // Stored order, with any newly introduced tabs appended at the end.
        var order = (defaults.stringArray(forKey: Self.tabOrderKey) ?? [])
            .compactMap(ModuleTab.init(rawValue:))
        for tab in ModuleTab.allCases where !order.contains(tab) {
            order.append(tab)
        }
        tabOrder = order
        launchAtLogin = SMAppService.mainApp.status == .enabled
        L10n.shared.language = language
        log.info("""
        loaded theme=\(self.theme.rawValue, privacy: .public) \
        idle=\(self.idleMode.rawValue, privacy: .public) \
        tabs=\(self.enabledTabs.count, privacy: .public)
        """)
    }

    func setWidgetPlacement(edge: WidgetEdge, offset: Double) {
        let clamped = min(max(offset, 0), 1)
        guard edge != widgetEdge || clamped != widgetOffset else { return }
        log.info("widget placement -> \(edge.rawValue, privacy: .public) @ \(clamped, privacy: .public)")
        widgetEdge = edge
        widgetOffset = clamped
    }

    func setWidgetPanelWidth(_ raw: CGFloat) {
        let clamped = Self.clampWidgetPanelWidth(raw)
        guard clamped != widgetPanelWidth else { return }
        widgetPanelWidth = clamped
    }

    private static func clampWidgetPanelWidth(_ width: CGFloat) -> CGFloat {
        var maxWidth = WidgetMetrics.panelMaxWidth
        if let screen = CapsuleGeometry.targetScreen {
            maxWidth = min(maxWidth, screen.frame.width - 80)
        }
        return min(max(width, WidgetMetrics.panelMinWidth), maxWidth)
    }

    func setWidgetPanelHeight(_ raw: CGFloat) {
        let clamped = Self.clampWidgetPanelHeight(raw)
        guard clamped != widgetPanelHeight else { return }
        widgetPanelHeight = clamped
    }

    private static func clampWidgetPanelHeight(_ height: CGFloat) -> CGFloat {
        var maxHeight = WidgetMetrics.panelMaxHeight
        if let screen = CapsuleGeometry.targetScreen {
            maxHeight = min(maxHeight, screen.visibleFrame.height - 2 * WidgetMetrics.edgeInset)
        }
        return min(max(height, WidgetMetrics.panelMinHeight), maxHeight)
    }

    func setPanelSize(_ raw: CGSize) {
        let clamped = Self.clampPanelSize(raw)
        guard clamped != expandedPanelSize else { return }
        log.info("panel size -> \(Int(clamped.width), privacy: .public)x\(Int(clamped.height), privacy: .public)")
        expandedPanelSize = clamped
    }

    /// The single authority on panel size limits. The screen bound lives
    /// here too: if the window were clamped separately from the stored size,
    /// SwiftUI would draw a capsule larger than its window and the bottom
    /// strip — including the resize grip — would be clipped into
    /// unreachability.
    private static func clampPanelSize(_ size: CGSize) -> CGSize {
        var maxSize = CapsuleMetrics.expandedMaxSize
        if let screen = CapsuleGeometry.targetScreen {
            maxSize.width = min(maxSize.width, screen.frame.width - 40)
            maxSize.height = min(maxSize.height, screen.frame.height * 2 / 3)
        }
        return CGSize(
            width: min(max(size.width, CapsuleMetrics.expandedMinSize.width), maxSize.width),
            height: min(max(size.height, CapsuleMetrics.expandedMinSize.height), maxSize.height)
        )
    }

    /// Re-clamp after display changes (a smaller screen may no longer fit
    /// the stored size).
    func revalidatePanelSize() {
        setPanelSize(expandedPanelSize)
    }

    func moveTabs(fromOffsets source: IndexSet, toOffset destination: Int) {
        tabOrder.move(fromOffsets: source, toOffset: destination)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            log.error("launch-at-login toggle failed: \(error, privacy: .public)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func isEnabled(_ tab: ModuleTab) -> Bool {
        enabledTabs.contains(tab)
    }

    /// The last enabled tab cannot be disabled — the panel needs content.
    func toggle(_ tab: ModuleTab) {
        if enabledTabs.contains(tab) {
            guard enabledTabs.count > 1 else { return }
            enabledTabs.remove(tab)
        } else {
            enabledTabs.insert(tab)
        }
    }
}
