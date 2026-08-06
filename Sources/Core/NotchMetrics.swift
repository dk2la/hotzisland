import CoreGraphics

enum NotchMetrics {
    /// Top "flared" corners — concave arcs blending the capsule into the
    /// screen edge (mimicking the physical notch fillets).
    static let closedTopRadius: CGFloat = 8
    static let closedBottomRadius: CGFloat = 12
    static let expandedTopRadius: CGFloat = 14
    static let expandedBottomRadius: CGFloat = 28

    static let expandedSize = CGSize(width: 480, height: 200)

    /// Capsule size on Macs without a physical notch.
    static let fallbackClosedSize = CGSize(width: 196, height: 32)

    /// Delay before shrinking the window after the close animation (ms).
    static let windowCollapseDelayMilliseconds = 450

    /// Width of each content area on the sides of the notch during a live event.
    static let eventSideWidth: CGFloat = 90

    /// How long a live event stays visible before auto-dismissing (ms).
    static let eventDisplayMilliseconds = 2500
}
