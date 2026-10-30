import Foundation
import Observation

/// State of the edge widget that SwiftUI animates on. Frames are set by the
/// controller in window-local SwiftUI coordinates, in the same runloop tick
/// as the window frame — the two must never disagree (see the capsule's
/// two-phase dance in CapsuleWindowController.requestState).
@MainActor
@Observable
final class WidgetViewModel {
    /// Open module panel; nil = collapsed to the icon strip.
    private(set) var selectedTab: ModuleTab?
    /// Widget rolled up to its grip plus the first module button (⌃⌥H);
    /// no panel. See WidgetGeometry.stripLength.
    var isMinimized = false

    var edge: WidgetEdge = .right
    var stripFrame: CGRect = .zero
    var panelFrame: CGRect = .zero

    @ObservationIgnored var onTabTapped: ((ModuleTab) -> Void)?
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

    func setSelectedTab(_ tab: ModuleTab?) {
        guard tab != selectedTab else { return }
        selectedTab = tab
    }
}
