import AppKit

@MainActor
enum CapsuleGeometry {
    /// The screen with a camera housing, falling back to the main screen.
    static var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Closed capsule size: exactly the camera housing plus margins for the
    /// top arcs, so the capsule body lines up with the camera housing seamlessly.
    static func closedSize(on screen: NSScreen) -> CGSize {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else {
            return CapsuleMetrics.fallbackClosedSize
        }

        let housingWidth = screen.frame.width - left.width - right.width
        return CGSize(
            width: housingWidth + CapsuleMetrics.closedTopRadius * 2,
            height: screen.safeAreaInsets.top
        )
    }

    /// The closed capsule widened by a content area on each side of the camera housing.
    static func capsule(_ closed: CGSize, side: CGFloat) -> CGSize {
        CGSize(width: closed.width + side * 2, height: closed.height)
    }

    /// `size` hanging from the top center of `screen`.
    static func topCentered(_ size: CGSize, on screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
