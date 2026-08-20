import SwiftUI

/// Hosting view for the island panel.
///
/// The panel never becomes key (it must not steal focus from the app the user
/// is working in), and AppKit swallows the first click into a non-key window
/// by default — which would make every button in the island require two
/// clicks. Accepting the first mouse restores single-click behaviour.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @MainActor @preconcurrency required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
