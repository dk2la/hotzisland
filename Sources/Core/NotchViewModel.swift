import Observation

@MainActor
@Observable
final class NotchViewModel {
    private(set) var state: NotchState = .closed

    /// Currently visible live event, if any. Shown only while not expanded.
    var activeEvent: LiveEvent?

    /// Selected tab of the expanded panel. Survives close/open cycles.
    private(set) var selectedTab: NotchTab = .playbooks

    /// Tabs have different panel sizes — the window controller resizes on change.
    @ObservationIgnored var onTabChange: ((NotchTab) -> Void)?

    /// Fired when a file drag hovers over the island — the controller
    /// expands it onto the shelf tab.
    @ObservationIgnored var onDragTargeted: (() -> Void)?

    /// True while the user drags the panel's resize grip — hover collapse
    /// is suppressed for the duration.
    @ObservationIgnored var isResizingPanel = false

    func selectTab(_ tab: NotchTab) {
        guard tab != selectedTab else { return }
        selectedTab = tab
        onTabChange?(tab)
    }

    func setState(_ newState: NotchState) {
        guard newState != state else { return }
        state = newState
    }
}
