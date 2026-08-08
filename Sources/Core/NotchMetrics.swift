import CoreGraphics

enum NotchMetrics {
    /// Top "flared" corners — concave arcs blending the capsule into the
    /// screen edge (mimicking the physical notch fillets).
    static let closedTopRadius: CGFloat = 8
    static let closedBottomRadius: CGFloat = 12
    static let expandedTopRadius: CGFloat = 14
    static let expandedBottomRadius: CGFloat = 28

    /// One user-resizable panel size shared by every tab — sizes that differ
    /// per tab made the island collapse when switching from a tall tab to a
    /// short one (the cursor ended up outside the shrunken capsule).
    /// The minimum fits the calendar, the largest layout.
    static let expandedMinSize = CGSize(width: 560, height: 300)
    static let expandedMaxSize = CGSize(width: 960, height: 620)

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
