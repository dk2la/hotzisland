import CoreGraphics

enum NotchMetrics {
    /// Top "flared" corners — concave arcs blending the capsule into the
    /// screen edge (mimicking the physical notch fillets).
    static let closedTopRadius: CGFloat = 8
    static let closedBottomRadius: CGFloat = 12
    static let expandedTopRadius: CGFloat = 14
    static let expandedBottomRadius: CGFloat = 28

    static let expandedSize = CGSize(width: 480, height: 200)
    /// The calendar needs a taller, wider panel than the other modules.
    static let calendarExpandedSize = CGSize(width: 560, height: 300)

    /// Visible island size for a tab — animated by SwiftUI.
    static func expandedSize(for tab: NotchTab) -> CGSize {
        tab == .calendar ? calendarExpandedSize : expandedSize
    }

    /// The window is always sized for the largest tab while expanded, so
    /// switching tabs animates purely inside SwiftUI. Resizing the window
    /// mid-animation resets the layout and reads as a redraw instead of a
    /// smooth expansion.
    static let expandedWindowSize = CGSize(
        width: max(expandedSize.width, calendarExpandedSize.width),
        height: max(expandedSize.height, calendarExpandedSize.height)
    )

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
