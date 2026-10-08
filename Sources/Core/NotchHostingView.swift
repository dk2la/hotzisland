import SwiftUI

/// Hosting view for the island panel.
///
/// The panel is key only while the settings are open (see
/// NotchPanel.allowsKeyFocus) — the rest of the time it stays non-key so it
/// does not steal focus from the app the user is working in. AppKit
/// swallows the first click into a non-key window by default, which would
/// make every button in the island require two clicks. Accepting the first
/// mouse restores single-click behaviour.
///
/// Hover comes from a tracking area on this view rather than a global
/// mouse-moved monitor: the window is exactly the island, so enter/exit
/// on the view is enter/exit on the island, and nothing runs while the
/// cursor is elsewhere on the screen.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    /// Points the island does not own (the menu bar beside the neck while
    /// expanded) fall through to whatever is underneath. View coordinates,
    /// y up.
    var ownsPoint: ((NSPoint) -> Bool)?

    /// Both controllers own the window frame and set it with `setFrame`
    /// in step with the state machine. The default `.standardBounds`
    /// sizing would make the hosting view install min/intrinsic/max
    /// constraints on top of that; the content is always laid out at the
    /// window's size, so SwiftUI has nothing to add.
    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    /// The view to install as the panel's `contentView`.
    ///
    /// Never the hosting view itself: as a window's content view
    /// `NSHostingView` animates the window frame to follow its content
    /// (`updateAnimatedWindowSize`, from `windowDidLayout`) regardless of
    /// `sizingOptions`. That races the controller's own `setFrame` — every
    /// window resize invalidates the safe area, which requests another
    /// update-constraints pass from inside the layout pass, and AppKit
    /// throws once the loop exceeds its budget (crashes on ⌃⌥H and on tab
    /// switches mid-animation). Behind a plain container the hosting view
    /// is an ordinary subview that just fills the window.
    func makeWindowContentView() -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear
        frame = container.bounds
        autoresizingMask = [.width, .height]
        container.addSubview(self)
        return container
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("unused")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if let ownsPoint, !ownsPoint(local) { return nil }
        return super.hitTest(point)
    }
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        // activeAlways: the app is an agent and never the active app.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}
