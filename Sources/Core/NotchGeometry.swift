import AppKit

@MainActor
enum NotchGeometry {
    /// The screen with a physical notch, falling back to the main screen.
    static var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Closed capsule size: exactly the physical notch plus margins for the
    /// top arcs, so the capsule body lines up with the notch seamlessly.
    static func closedSize(on screen: NSScreen) -> CGSize {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else {
            return NotchMetrics.fallbackClosedSize
        }

        let notchWidth = screen.frame.width - left.width - right.width
        return CGSize(
            width: notchWidth + NotchMetrics.closedTopRadius * 2,
            height: screen.safeAreaInsets.top
        )
    }
}
