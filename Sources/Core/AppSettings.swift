import Foundation
import Observation
import OSLog

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

    private(set) var enabledTabs: Set<NotchTab> {
        didSet {
            defaults.set(enabledTabs.map(\.rawValue).sorted(), forKey: Self.tabsKey)
            onChange?()
        }
    }

    /// The window controller re-evaluates the island's idle state on changes.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "settings")
    @ObservationIgnored private static let themeKey = "settings.theme"
    @ObservationIgnored private static let idleKey = "settings.idleMode"
    @ObservationIgnored private static let tabsKey = "settings.enabledTabs"

    init() {
        let defaults = UserDefaults.standard
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
        log.info("""
        loaded theme=\(self.theme.rawValue, privacy: .public) \
        idle=\(self.idleMode.rawValue, privacy: .public) \
        tabs=\(self.enabledTabs.count, privacy: .public)
        """)
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
