import Foundation
import Observation
import OSLog
import ServiceManagement

/// Island shell appearance.
enum IslandTheme: String, CaseIterable, Identifiable {
    case stealth
    case glass
    case glow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stealth: "Stealth"
        case .glass: "Glass"
        case .glow: "Glow"
        }
    }

    var subtitle: String {
        switch self {
        case .stealth: "Pure black — blends into the notch."
        case .glass: "Dark translucent material."
        case .glow: "Accent ring tinted by the current artwork."
        }
    }
}

/// What the island does when nothing demands attention.
enum IdleMode: String, CaseIterable, Identifiable {
    /// Always shrink to the bare notch.
    case invisible
    /// Show compact indicators (playing track, running timer).
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .invisible: "Invisible"
        case .compact: "Compact indicators"
        }
    }
}

/// Where the module panel lives: attached to the notch or as a free
/// edge-docked widget. Live events stay on the notch in both modes.
enum DisplayMode: String, CaseIterable, Identifiable {
    case island
    case widget

    var id: String { rawValue }

    var title: String {
        switch self {
        case .island: "Island"
        case .widget: "Widget"
        }
    }
}

/// User preferences, persisted to UserDefaults.
@MainActor
@Observable
final class AppSettings {
    var theme: IslandTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Self.themeKey)
            log.info("theme -> \(self.theme.rawValue, privacy: .public)")
            notifyChange()
        }
    }

    var idleMode: IdleMode {
        didSet {
            defaults.set(idleMode.rawValue, forKey: Self.idleKey)
            log.info("idleMode -> \(self.idleMode.rawValue, privacy: .public)")
            notifyChange()
        }
    }

    var displayMode: DisplayMode {
        didSet {
            defaults.set(displayMode.rawValue, forKey: Self.displayModeKey)
            log.info("displayMode -> \(self.displayMode.rawValue, privacy: .public)")
            notifyChange()
            onDisplayModeChange?(displayMode)
        }
    }

    /// Widget glass appearance (the island is always dark glass).
    var glassAppearance: GlassAppearance {
        didSet {
            defaults.set(glassAppearance.rawValue, forKey: Self.glassAppearanceKey)
            log.info("glassAppearance -> \(self.glassAppearance.rawValue, privacy: .public)")
            notifyChange()
        }
    }

    /// Interface language — translates the widget, island and settings.
    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Self.languageKey)
            L10n.shared.language = language
            log.info("language -> \(self.language.rawValue, privacy: .public)")
            notifyChange()
        }
    }

    /// Edge the widget strip is docked to (widget mode only).
    private(set) var widgetEdge: WidgetEdge {
        didSet {
            defaults.set(widgetEdge.rawValue, forKey: Self.widgetEdgeKey)
            notifyChange()
        }
    }

    /// Normalized 0…1 position of the strip's center along its edge.
    private(set) var widgetOffset: Double {
        didSet {
            defaults.set(widgetOffset, forKey: Self.widgetOffsetKey)
            notifyChange()
        }
    }

    /// Clicking anywhere outside the widget closes the open panel. Off =
    /// the panel stays pinned until closed explicitly. ⌃⌥P flips it.
    var closeOnOutsideClick: Bool {
        didSet {
            defaults.set(closeOnOutsideClick, forKey: Self.outsideClickKey)
            log.info("closeOnOutsideClick -> \(self.closeOnOutsideClick, privacy: .public)")
            notifyChange()
        }
    }

    /// Widget collapsed to a small square (⌃⌥H). Persisted so a restart
    /// brings the widget back the way it was left.
    var widgetMinimized: Bool {
        didSet {
            defaults.set(widgetMinimized, forKey: Self.widgetMinimizedKey)
            log.info("widgetMinimized -> \(self.widgetMinimized, privacy: .public)")
            notifyChange()
        }
    }

    /// User-chosen size of the expanded panel (dragged by the corner grip).
    private(set) var expandedPanelSize: CGSize {
        didSet {
            defaults.set(Double(expandedPanelSize.width), forKey: Self.panelWidthKey)
            defaults.set(Double(expandedPanelSize.height), forKey: Self.panelHeightKey)
            notifyChange()
        }
    }

    private(set) var enabledTabs: Set<NotchTab> {
        didSet {
            defaults.set(enabledTabs.map(\.rawValue).sorted(), forKey: Self.tabsKey)
            notifyChange()
        }
    }

    /// User-arranged channel order (onboarding step 3 / settings → Модули).
    private(set) var tabOrder: [NotchTab] {
        didSet {
            defaults.set(tabOrder.map(\.rawValue), forKey: Self.tabOrderKey)
            notifyChange()
        }
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

    /// The AppDelegate creates/tears down the widget window on mode switches.
    @ObservationIgnored var onDisplayModeChange: ((DisplayMode) -> Void)?

    func addChangeHandler(_ handler: @escaping () -> Void) {
        changeHandlers.append(handler)
    }

    private func notifyChange() {
        for handler in changeHandlers {
            handler()
        }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "settings")
    @ObservationIgnored private static let themeKey = "settings.theme"
    @ObservationIgnored private static let idleKey = "settings.idleMode"
    // v4: bumped when the email tab shipped (v3 = notes, v2 = playbooks) —
    // a stored older set would silently hide new tabs, since "missing" is
    // indistinguishable from "disabled by the user".
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
    @ObservationIgnored private static let displayModeKey = "settings.displayMode"
    @ObservationIgnored private static let glassAppearanceKey = "settings.glassAppearance"
    @ObservationIgnored private static let languageKey = "settings.language"
    @ObservationIgnored private static let widgetEdgeKey = "settings.widgetEdge"
    @ObservationIgnored private static let widgetOffsetKey = "settings.widgetOffset"
    @ObservationIgnored private static let outsideClickKey = "settings.closeOnOutsideClick"
    @ObservationIgnored private static let widgetMinimizedKey = "settings.widgetMinimized"

    init() {
        let defaults = UserDefaults.standard
        let storedWidth = defaults.double(forKey: Self.panelWidthKey)
        let storedHeight = defaults.double(forKey: Self.panelHeightKey)
        expandedPanelSize = Self.clampPanelSize(CGSize(
            width: storedWidth > 0 ? storedWidth : NotchMetrics.expandedMinSize.width,
            height: storedHeight > 0 ? storedHeight : NotchMetrics.expandedMinSize.height
        ))
        theme = defaults.string(forKey: Self.themeKey)
            .flatMap(IslandTheme.init(rawValue:)) ?? .stealth
        idleMode = defaults.string(forKey: Self.idleKey)
            .flatMap(IdleMode.init(rawValue:)) ?? .compact
        displayMode = defaults.string(forKey: Self.displayModeKey)
            .flatMap(DisplayMode.init(rawValue:)) ?? .island
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
        mode=\(self.displayMode.rawValue, privacy: .public) \
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
