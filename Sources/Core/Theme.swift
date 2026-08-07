import SwiftUI

/// Design tokens — the single source of truth for colors, typography, shapes
/// and motion. Views must not use raw colors/fonts/springs directly.
/// Phase 6 evolves this into switchable themes (Stealth / Glow / Glass).
enum Theme {
    // MARK: - Colors

    static let islandFill = Color.black
    static let surface = Color.white.opacity(0.08)
    static let track = Color.white.opacity(0.25)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.85)
    static let textTertiary = Color.white.opacity(0.45)
    static let textQuaternary = Color.white.opacity(0.35)
    static let iconMuted = Color.white.opacity(0.7)

    static let accentPositive = Color.green
    /// Today's marker in the calendar grid.
    static let accentToday = Color.red
    /// Elevated but not critical load (60–85%).
    static let accentWarning = Color.orange
    /// Critical load (85%+).
    static let accentCritical = Color.red

    // MARK: - Shape

    static let surfaceRadius: CGFloat = 12

    // MARK: - Typography

    /// Large numeric value (e.g. battery percent).
    static let valueFont = Font.system(size: 20, weight: .bold, design: .rounded)
    /// Small numeric value (e.g. percent in a live event).
    static let smallValueFont = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let headlineFont = Font.system(size: 13, weight: .semibold)
    static let bodyFont = Font.system(size: 11, weight: .medium)
    static let captionFont = Font.system(size: 10)
    /// Day numbers in the calendar grid.
    static let dayFont = Font.system(size: 11, weight: .medium, design: .rounded)

    static let iconFont = Font.system(size: 14, weight: .semibold)
    static let iconSmallFont = Font.system(size: 12, weight: .semibold)
    static let iconLargeFont = Font.system(size: 22, weight: .medium)
    static let tabIconFont = Font.system(size: 13, weight: .semibold)

    /// Semibold icon at an arbitrary size (transport controls etc.).
    static func iconFont(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }

    // MARK: - Motion

    /// Island open/close.
    static let stateSpring = Animation.spring(response: 0.38, dampingFraction: 0.78)
    /// Live event bulge.
    static let eventSpring = Animation.spring(response: 0.32, dampingFraction: 0.8)
}
