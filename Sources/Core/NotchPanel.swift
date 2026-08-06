import AppKit

/// Borderless non-activating panel over the notch: above the menu bar,
/// on all Spaces, visible over fullscreen apps.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Must come after `isFloatingPanel`, which silently resets the level
        // to `.floating` — otherwise the island ends up below menu bar icons.
        level = .screenSaver
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// By default macOS keeps windows out of the menu bar territory —
    /// a window living in the notch must opt out of that constraint.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
