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

    @MainActor @preconcurrency required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
