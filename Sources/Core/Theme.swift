import SwiftUI

/// Design tokens — "Instrument" design system (Hotzisland DS v3).
/// Studio-hardware aesthetic: matte black, hairlines, mono readouts, one
/// warm amber accent. The norm is darkness — light means activity; red
/// appears only for critical states. Data is set in monospace, prose in the
/// system face. Views must not use raw colors/fonts/springs directly.
enum Theme {
    // MARK: - Colors

    /// shell/void — the capsule itself.
    static let islandFill = Color.black
    /// Inner instrument cells and cards.
    static let cardFill = Color(red: 0.051, green: 0.051, blue: 0.047) // #0D0D0C
    /// Raised controls (key buttons, toggles).
    static let raisedFill = Color(red: 0.110, green: 0.110, blue: 0.102) // #1C1C1A
    /// Windows (settings, onboarding).
    static let panelFill = Color(red: 0.071, green: 0.071, blue: 0.067) // #121211

    /// Warm paper white.
    static let textPrimary = Color(red: 0.949, green: 0.945, blue: 0.925) // #F2F1EC
    static let textSecondary = textPrimary.opacity(0.72)
    static let textTertiary = textPrimary.opacity(0.50)
    static let textQuaternary = textPrimary.opacity(0.38)
    static let textFaint = textPrimary.opacity(0.32)

    static let hairline = textPrimary.opacity(0.12)
    static let hairlineSoft = textPrimary.opacity(0.08)
    static let controlBorder = textPrimary.opacity(0.14)
    static let dashedBorder = textPrimary.opacity(0.18)
    /// Unfilled segments of meters.
    static let segmentOff = textPrimary.opacity(0.15)
    /// Filled segments below the warning threshold.
    static let segmentOn = textPrimary.opacity(0.70)
    /// Island edge (top edge is masked off at the notch seam).
    static let islandBorder = textPrimary.opacity(0.10)

    /// The only chromatic accent — neon green #3FFF00 (user's pick over the
    /// DS's original amber).
    static let accent = Color(red: 0.247, green: 1.0, blue: 0.0)
    /// state/critical — oklch(0.62 0.19 25). Critical only, never decoration.
    static let critical = Color(red: 0.84, green: 0.29, blue: 0.22)

    static let accentBorder = accent.opacity(0.35)
    static let accentWash = accent.opacity(0.07)

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

    /// Inner elements (cards, instrument cells).
    static let cardRadius: CGFloat = 6
    /// Buttons and key caps.
    static let controlRadius: CGFloat = 5
    static let surfaceRadius: CGFloat = 6
    /// Uniform inner inset of the expanded panel.
    static let panelInset: CGFloat = 14

    // MARK: - Typography
    // Rule: anything that changes over time — time, percentages, rates,
    // countdowns — is monospace. Prose is the system face.

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Instrument captions (CPU · MEM · REC) — use with `.kerning(1.2)`.
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
    static let captionFont = mono(10)
    static let valueFont = readoutLFont
    static let smallValueFont = mono(12, .medium)
    static let dayFont = mono(11)
    static let iconFont = Font.system(size: 14, weight: .semibold)
    static let iconSmallFont = Font.system(size: 12, weight: .semibold)
    static let iconLargeFont = Font.system(size: 22, weight: .medium)
    static let tabIconFont = Font.system(size: 13, weight: .semibold)

    static func iconFont(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }

    // MARK: - Motion
    // Data never animates — readouts jump like real instruments. Springs
    // exist only for capsule geometry; indicators may blink.

    /// Island open/close — drier than before.
    static let stateSpring = Animation.spring(response: 0.30, dampingFraction: 0.82)
    /// Live event bulge.
    static let eventSpring = Animation.spring(response: 0.24, dampingFraction: 0.76)
}
