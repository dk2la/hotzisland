import Foundation
import Observation
import OSLog
import ServiceManagement

/// Island shell appearance.
enum IslandTheme: String {
    case stealth
    case glass
    case glow
}

/// What the island does when nothing demands attention.
enum IdleMode: String {
    /// Always shrink to the bare notch.
    case invisible
    /// Show compact indicators (playing track, running timer).
    case compact
}

extension Notification.Name {
    /// Posted by widget UI that wants the settings island opened; the
    /// AppDelegate observes it.
    static let hotzOpenSettings = Notification.Name("hotzOpenSettings")
    /// Posted with `userInfo["tab"]` (a NotchTab raw value) to open that
    /// module in the widget — e.g. the assistant handing a form to the
    /// calendar.
    static let hotzShowModule = Notification.Name("hotzShowModule")
}

/// Asks the AppDelegate for the settings island, optionally on a page.
@MainActor
func requestSettings(page: SettingsView.Page? = nil) {
    NotificationCenter.default.post(
        name: .hotzOpenSettings,
        object: nil,
        userInfo: page.map { ["page": $0.rawValue] }
    )
}

/// User preferences, persisted to UserDefaults.
@MainActor
@Observable
final class AppSettings {
    var theme: IslandTheme {
        didSet { persist(theme.rawValue, Self.themeKey, log: "theme") }
    }

    var idleMode: IdleMode {
        didSet { persist(idleMode.rawValue, Self.idleKey, log: "idleMode") }
    }

    /// Widget glass appearance (the island is always dark glass).
    var glassAppearance: GlassAppearance {
        didSet { persist(glassAppearance.rawValue, Self.glassAppearanceKey, log: "glassAppearance") }
    }

    /// Interface language — translates the widget, island and settings.
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

    /// Size of the widget-mode panel, each axis dragged by its own grip.
    /// Separate from the island's `expandedPanelSize` — the two surfaces
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

    private(set) var enabledTabs: Set<NotchTab> {
        didSet { persist(enabledTabs.map(\.rawValue).sorted(), Self.tabsKey) }
    }

    /// User-arranged channel order (onboarding step 3 / settings → Модули).
    private(set) var tabOrder: [NotchTab] {
        didSet { persist(tabOrder.map(\.rawValue), Self.tabOrderKey) }
    }

    /// Launch-at-login through SMAppService; mirrored here for observation.
    private(set) var launchAtLogin: Bool

    /// Channels in user order, disabled ones filtered out.
    var orderedEnabledTabs: [NotchTab] {
        tabOrder.filter { enabledTabs.contains($0) }
    }

    /// Both window controllers react to changes — the notch re-evaluates its
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
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "settings")
    @ObservationIgnored private static let themeKey = "settings.theme"
    @ObservationIgnored private static let idleKey = "settings.idleMode"
    // v5: bumped when the assistant tab shipped (v4 = email, v3 = notes,
    // v2 = playbooks) — a stored older set would silently hide new tabs,
    // since "missing" is indistinguishable from "disabled by the user".
    @ObservationIgnored private static let tabsKey = "settings.enabledTabs.v5"
    /// (legacy key, tabs to surface when migrating from it)
    @ObservationIgnored private static let legacyTabsKeys: [(String, Set<NotchTab>)] = [
        ("settings.enabledTabs.v4", [.assistant]),
        ("settings.enabledTabs.v3", [.email, .assistant]),
        ("settings.enabledTabs.v2", [.notes, .email, .assistant]),
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
    @ObservationIgnored private static let widgetPanelWidthKey = "settings.widgetPanelWidth"
    @ObservationIgnored private static let widgetPanelHeightKey = "settings.widgetPanelHeight"

    init() {
        let defaults = UserDefaults.standard
        let storedWidth = defaults.double(forKey: Self.panelWidthKey)
        let storedHeight = defaults.double(forKey: Self.panelHeightKey)
        expandedPanelSize = Self.clampPanelSize(CGSize(
            width: storedWidth > 0 ? storedWidth : NotchMetrics.expandedMinSize.width,
            height: storedHeight > 0 ? storedHeight : NotchMetrics.expandedMinSize.height
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
            .flatMap(IslandTheme.init(rawValue:)) ?? .stealth
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
        // Coming-soon modules stay off until their services land.
        let defaultEnabled = Set(NotchTab.allCases).subtracting(NotchTab.comingSoon)
        if let stored = defaults.stringArray(forKey: Self.tabsKey) {
            let tabs = Set(stored.compactMap(NotchTab.init(rawValue:)))
            enabledTabs = tabs.isEmpty ? defaultEnabled : tabs
        } else if let (legacy, extras) = Self.legacyTabsKeys
            .compactMap({ key, extras in
                defaults.stringArray(forKey: key).map { ($0, extras) }
            })
            .first {
            // Migration: keep the user's choices, surface freshly shipped
            // tabs they could not have known about.
            let tabs = Set(legacy.compactMap(NotchTab.init(rawValue:))).union(extras)
            enabledTabs = tabs.isEmpty ? defaultEnabled : tabs
        } else {
            enabledTabs = defaultEnabled
        }
        // Stored order, with any newly introduced tabs appended at the end.
        var order = (defaults.stringArray(forKey: Self.tabOrderKey) ?? [])
            .compactMap(NotchTab.init(rawValue:))
        for tab in NotchTab.allCases where !order.contains(tab) {
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
        if let screen = NotchGeometry.targetScreen {
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
        if let screen = NotchGeometry.targetScreen {
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
    /// SwiftUI would draw an island larger than its window and the bottom
    /// strip — including the resize grip — would be clipped into
    /// unreachability.
    private static func clampPanelSize(_ size: CGSize) -> CGSize {
        var maxSize = NotchMetrics.expandedMaxSize
        if let screen = NotchGeometry.targetScreen {
            maxSize.width = min(maxSize.width, screen.frame.width - 40)
            maxSize.height = min(maxSize.height, screen.frame.height * 2 / 3)
        }
        return CGSize(
            width: min(max(size.width, NotchMetrics.expandedMinSize.width), maxSize.width),
            height: min(max(size.height, NotchMetrics.expandedMinSize.height), maxSize.height)
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

    func isEnabled(_ tab: NotchTab) -> Bool {
        enabledTabs.contains(tab)
    }

    /// The last enabled tab cannot be disabled — the panel needs content.
    func toggle(_ tab: NotchTab) {
        if enabledTabs.contains(tab) {
            guard enabledTabs.count > 1 else { return }
            enabledTabs.remove(tab)
        } else {
            enabledTabs.insert(tab)
        }
    }
}
