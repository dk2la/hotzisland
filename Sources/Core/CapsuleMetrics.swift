import CoreGraphics

enum CapsuleMetrics {
    /// Top "flared" corners — concave arcs blending the capsule into the
    /// screen edge (mimicking the camera housing fillets).
    // Instrument DS: harder corners — closed capsule 8 top / 10 bottom.
    static let closedTopRadius: CGFloat = 8
    static let closedBottomRadius: CGFloat = 10

    /// The expanded capsule hosts the settings UI (sidebar + page), so the
    /// minimum is what that layout needs; the user can grow it from there.
    static let expandedMinSize = CGSize(width: 720, height: 520)
    static let expandedMaxSize = CGSize(width: 1100, height: 760)

    /// The welcome tour's body. Fixed, and small enough for the smallest
    /// supported screen, so it needs none of the settings' clamping.
    static let onboardingSize = CGSize(width: 600, height: 560)

    /// Corner radius of the expanded capsule's body — the large, soft
    /// corners of a floating glass sheet.
    static let dropRadius: CGFloat = 30

    /// Below the menu bar the drop keeps the housing's black for this long
    /// before it has fully turned into glass.
    static let dropInkFade: CGFloat = 70

    /// Expanded capsule: the drop's concave shoulders below the menu bar,
    /// where the housing-wide neck widens into the panel.
    static let dropFillet: CGFloat = 14

    /// Capsule size on Macs without a camera housing.
    static let fallbackClosedSize = CGSize(width: 196, height: 32)

    /// Delay before shrinking the window after the close animation (ms).
    static let windowCollapseDelayMilliseconds = 450

    /// Width of each content area on the sides of the camera housing during a live event.
    static let eventSideWidth: CGFloat = 90

    /// Width of each side area in the compact (persistent) state, e.g. the
    /// playing-track indicator.
    static let compactSideWidth: CGFloat = 56

    /// How long a live event stays visible before auto-dismissing (ms).
    static let eventDisplayMilliseconds = 2500
}
