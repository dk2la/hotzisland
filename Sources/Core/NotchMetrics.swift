import CoreGraphics

enum NotchMetrics {
    /// Top "flared" corners — concave arcs blending the capsule into the
    /// screen edge (mimicking the physical notch fillets).
    // Instrument DS: harder corners — closed capsule 8 top / 10 bottom,
    // expanded panel 10 all round.
    static let closedTopRadius: CGFloat = 8
    static let closedBottomRadius: CGFloat = 10
    static let expandedTopRadius: CGFloat = 10
    static let expandedBottomRadius: CGFloat = 10

    /// The expanded island hosts the settings UI (sidebar + page), so the
    /// minimum is what that layout needs; the user can grow it from there.
    static let expandedMinSize = CGSize(width: 720, height: 520)
    static let expandedMaxSize = CGSize(width: 1100, height: 760)

    /// Capsule size on Macs without a physical notch.
    static let fallbackClosedSize = CGSize(width: 196, height: 32)

    /// Delay before shrinking the window after the close animation (ms).
    static let windowCollapseDelayMilliseconds = 450

    /// Width of each content area on the sides of the notch during a live event.
    static let eventSideWidth: CGFloat = 90

    /// Width of each side area in the compact (persistent) state, e.g. the
    /// playing-track indicator.
    static let compactSideWidth: CGFloat = 56

    /// How long a live event stays visible before auto-dismissing (ms).
    static let eventDisplayMilliseconds = 2500
}
