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

/// User preferences, persisted to UserDefaults.
@MainActor
@Observable
final class AppSettings {
    var theme: IslandTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Self.themeKey)
            log.info("theme -> \(self.theme.rawValue, privacy: .public)")
            onChange?()
        }
    }

    var idleMode: IdleMode {
        didSet {
            defaults.set(idleMode.rawValue, forKey: Self.idleKey)
            log.info("idleMode -> \(self.idleMode.rawValue, privacy: .public)")
            onChange?()
        }
    }

    /// User-chosen size of the expanded panel (dragged by the corner grip).
    private(set) var expandedPanelSize: CGSize {
        didSet {
            defaults.set(Double(expandedPanelSize.width), forKey: Self.panelWidthKey)
            defaults.set(Double(expandedPanelSize.height), forKey: Self.panelHeightKey)
            onChange?()
        }
    }

    private(set) var enabledTabs: Set<NotchTab> {
        didSet {
            defaults.set(enabledTabs.map(\.rawValue).sorted(), forKey: Self.tabsKey)
            onChange?()
        }
    }

    /// User-arranged channel order (onboarding step 3 / settings → Модули).
    private(set) var tabOrder: [NotchTab] {
        didSet {
            defaults.set(tabOrder.map(\.rawValue), forKey: Self.tabOrderKey)
            onChange?()
        }
    }

    /// Launch-at-login through SMAppService; mirrored here for observation.
    private(set) var launchAtLogin: Bool

    /// Channels in user order, disabled ones filtered out.
    var orderedEnabledTabs: [NotchTab] {
        tabOrder.filter { enabledTabs.contains($0) }
    }

    /// The window controller re-evaluates the island's idle state on changes.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "settings")
    @ObservationIgnored private static let themeKey = "settings.theme"
    @ObservationIgnored private static let idleKey = "settings.idleMode"
    // v2: bumped when the playbooks tab was added — a stored v1 set would
    // silently hide new tabs, since "missing" is indistinguishable from
    // "disabled by the user".
    @ObservationIgnored private static let tabsKey = "settings.enabledTabs.v2"
    @ObservationIgnored private static let panelWidthKey = "settings.panelWidth"
    @ObservationIgnored private static let panelHeightKey = "settings.panelHeight"
    @ObservationIgnored private static let tabOrderKey = "settings.tabOrder"

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
        if let stored = defaults.stringArray(forKey: Self.tabsKey) {
            let tabs = Set(stored.compactMap(NotchTab.init(rawValue:)))
            enabledTabs = tabs.isEmpty ? Set(NotchTab.allCases) : tabs
        } else {
            enabledTabs = Set(NotchTab.allCases)
        }
        // Stored order, with any newly introduced tabs appended at the end.
        var order = (defaults.stringArray(forKey: Self.tabOrderKey) ?? [])
            .compactMap(NotchTab.init(rawValue:))
        for tab in NotchTab.allCases where !order.contains(tab) {
            order.append(tab)
        }
        tabOrder = order
        launchAtLogin = SMAppService.mainApp.status == .enabled
        log.info("""
        loaded theme=\(self.theme.rawValue, privacy: .public) \
        idle=\(self.idleMode.rawValue, privacy: .public) \
        tabs=\(self.enabledTabs.count, privacy: .public)
        """)
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
