import Observation

@MainActor
@Observable
final class NotchViewModel {
    private(set) var state: NotchState = .closed

    /// Currently visible live event, if any. Shown only while not expanded.
    var activeEvent: LiveEvent?

    /// Which settings page the expanded island shows; module UI deep-links
    /// into it ("Set up account" → Accounts).
    let pageSelection = SettingsPageSelection()

    /// Fired by a click on the resting island — the controller expands it
    /// into the settings panel.
    @ObservationIgnored var onIslandTapped: (() -> Void)?

    /// Fired by the panel's close button.
    @ObservationIgnored var onClose: (() -> Void)?

    /// True while the user drags the panel's resize grip — outside-click
    /// collapse is suppressed for the duration.
    @ObservationIgnored var isResizingPanel = false

    func setState(_ newState: NotchState) {
        guard newState != state else { return }
        state = newState
    }
}
