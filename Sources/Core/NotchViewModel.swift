import Observation

@MainActor
@Observable
final class NotchViewModel {
    private(set) var state: NotchState = .closed

    /// Currently visible live event, if any. Shown only while not expanded.
    var activeEvent: LiveEvent?

    /// Selected tab of the expanded panel. Survives close/open cycles.
    var selectedTab: NotchTab = .devices

    func setState(_ newState: NotchState) {
        guard newState != state else { return }
        state = newState
    }
}
