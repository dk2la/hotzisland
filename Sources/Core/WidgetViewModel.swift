import Foundation
import Observation

/// State of the edge widget that SwiftUI animates on. Frames are set by the
/// controller in window-local SwiftUI coordinates, in the same runloop tick
/// as the window frame — the two must never disagree (see the notch's
/// two-phase dance in NotchWindowController.requestState).
@MainActor
@Observable
final class WidgetViewModel {
    /// Open module panel; nil = collapsed to the icon strip.
    private(set) var selectedTab: NotchTab?
    /// Widget shrunk to a small square (⌃⌥H); no strip, no panel.
    var isMinimized = false

    var edge: WidgetEdge = .right
    var stripFrame: CGRect = .zero
    var panelFrame: CGRect = .zero

    @ObservationIgnored var onTabTapped: ((NotchTab) -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored var onRestore: (() -> Void)?
    /// Drag reads the global cursor itself (NSEvent.mouseLocation) — the
    /// window moves mid-drag, so gesture-local coordinates would feed back.
    @ObservationIgnored var onDragChanged: (() -> Void)?
    @ObservationIgnored var onDragEnded: (() -> Void)?
    /// Resize grips (width on the panel's outer edge, height on the bottom).
    /// They read the global cursor for the same feedback reason as the drag.
    @ObservationIgnored var onResizeChanged: (() -> Void)?
    @ObservationIgnored var onResizeEnded: (() -> Void)?
    @ObservationIgnored var onHeightResizeChanged: (() -> Void)?
    @ObservationIgnored var onHeightResizeEnded: (() -> Void)?

    func setSelectedTab(_ tab: NotchTab?) {
        guard tab != selectedTab else { return }
        selectedTab = tab
    }
}
