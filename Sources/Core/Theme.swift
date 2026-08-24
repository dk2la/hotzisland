import SwiftUI

/// Design tokens — "HotzIsland V3" design system, visionOS material language.
/// Glass surfaces over the desktop, white vibrancy instead of color, circular
/// controls, SF Pro. The one allowed accent is a solid white surface with a
/// dark glyph; red appears only for critical states and badges.
/// Views must not use raw colors/fonts/springs directly.
enum Theme {
    // MARK: - Colors

    /// shell/void — the notch housing itself stays hardware black.
    static let islandFill = Color.black
    /// Inner cells and cards: raised glass on top of the window material.
    static let cardFill = Color.white.opacity(0.06)
    /// Raised controls (buttons, toggles, chips).
    static let raisedFill = Color.white.opacity(0.12)
    /// Windows (settings, onboarding) — opaque fallback surface.
    static let panelFill = Color(red: 0.071, green: 0.071, blue: 0.067) // #121211

    /// White vibrancy ramp.
    static let textPrimary = Color.white
    static let textSecondary = textPrimary.opacity(0.72)
    static let textTertiary = textPrimary.opacity(0.50)
    static let textQuaternary = textPrimary.opacity(0.38)
    static let textFaint = textPrimary.opacity(0.32)

    /// Dark glyph sitting on a solid accent control.
    static let inkOnAccent = Color(red: 0.043, green: 0.043, blue: 0.039) // #0B0B0A

    static let hairline = textPrimary.opacity(0.12)
    static let hairlineSoft = textPrimary.opacity(0.08)
    static let controlBorder = textPrimary.opacity(0.14)
    static let dashedBorder = textPrimary.opacity(0.25)
    /// Unfilled segments of meters.
    static let segmentOff = textPrimary.opacity(0.15)
    /// Filled segments below the warning threshold.
    static let segmentOn = textPrimary.opacity(0.70)
    /// Island edge (top edge is masked off at the notch seam).
    static let islandBorder = textPrimary.opacity(0.10)

    /// The one chromatic accent — acid green, the app's signature. Solid
    /// accent controls carry `inkOnAccent` glyphs.
    static let accent = Color(red: 0.247, green: 1.0, blue: 0.0) // #3FFF00
    /// state/critical — badges and critical meters only, never decoration.
    static let critical = Color(red: 1.0, green: 0.27, blue: 0.29)

    static let accentBorder = accent.opacity(0.4)
    static let accentWash = accent.opacity(0.10)

    // MARK: - Glass material

    /// Tint laid over `.ultraThinMaterial` for the two appearances.
    static let glassTintLight = Color.white.opacity(0.09)
    static let glassTintDark = Color.black.opacity(0.52)
    static let glassStrokeLight = Color.white.opacity(0.20)
    static let glassStrokeDark = Color.white.opacity(0.14)

    // MARK: - Severity

    /// White below 60%, accent from 60%, red from 85% — instrument rules.
    static func severity(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: segmentOn
        case ..<0.85: accent
        default: critical
        }
    }

    // MARK: - Shape & layout grid
    // Squarish glass: rounded rectangles, never full capsules.

    /// Windows: the expanded panel, the widget panel.
    static let windowRadius: CGFloat = 18
    /// Inner elements (cards, rows, tiles).
    static let cardRadius: CGFloat = 12
    /// Buttons and key caps.
    static let controlRadius: CGFloat = 9
    static let surfaceRadius: CGFloat = 12
    /// Uniform inner inset of the expanded panel.
    static let panelInset: CGFloat = 14

    // MARK: - Typography
    // Rule: anything that changes over time — time, percentages, rates,
    // countdowns — is monospace. Prose is the system face.

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Instrument captions (CPU · MEM · MEDIA) — use with `.kerning(1.2)`.
    static let labelFont = mono(9.5, .medium)
    /// Large readout (percent cells).
    static let readoutLFont = mono(22)
    static let readoutMFont = mono(13)
    static let readoutSFont = mono(10.5)
    /// The big countdown.
    static let timerFont = mono(44)

    static let titleFont = Font.system(size: 15, weight: .semibold)
    static let headlineFont = Font.system(size: 13, weight: .semibold)
    static let bodyFont = Font.system(size: 13)
    static let subFont = Font.system(size: 12)

    // Legacy aliases still used by shared chrome.
    static let captionFont = Font.system(size: 10.5)
    static let valueFont = readoutLFont
    static let smallValueFont = mono(12, .medium)
    static let dayFont = mono(11)
    static let iconFont = Font.system(size: 14, weight: .semibold)
    static let iconSmallFont = Font.system(size: 12, weight: .semibold)
    static let iconLargeFont = Font.system(size: 22, weight: .medium)
    static let tabIconFont = Font.system(size: 15, weight: .medium)

    static func iconFont(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }

    // MARK: - Motion
    // Data never animates — readouts jump like real instruments. Springs
    // exist only for surface geometry; indicators may blink.

    /// Island open/close, panel open/close.
    static let stateSpring = Animation.spring(response: 0.30, dampingFraction: 0.82)
    /// Live event bulge — the one place bounce is allowed.
    static let eventSpring = Animation.spring(response: 0.24, dampingFraction: 0.76)
}
