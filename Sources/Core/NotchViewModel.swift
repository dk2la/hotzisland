import CoreGraphics
import Observation

/// What the expanded island hosts.
enum IslandContent: Equatable {
    case settings
    case onboarding
}

@MainActor
@Observable
final class NotchViewModel {
    private(set) var state: NotchState = .closed

    /// Currently visible live event, if any. Shown only while not expanded.
    var activeEvent: LiveEvent?

    /// The expanded island's content. Set by the controller, which also
    /// sizes the window for it.
    var content: IslandContent = .settings

    /// Which settings page the expanded island shows; module UI deep-links
    /// into it ("Set up account" → Accounts).
    let pageSelection = SettingsPageSelection()

    /// The tour's page. Kept here rather than in the view so a detour into
    /// the settings (connecting an account) can come back to the same page.
    var onboardingStep: OnboardingStep = .welcome

    /// The settings were opened from the tour — they offer the way back.
    var cameFromOnboarding = false

    /// Fired by a click on the resting island — the controller expands it
    /// into the settings panel.
    @ObservationIgnored var onIslandTapped: (() -> Void)?

    /// Fired by the panel's close button.
    @ObservationIgnored var onClose: (() -> Void)?

    /// Fired by "back to tour" in the settings.
    @ObservationIgnored var onResumeOnboarding: (() -> Void)?

    /// True while the user drags the panel's resize grip — outside-click
    /// collapse is suppressed for the duration.
    @ObservationIgnored var isResizingPanel = false

    func setState(_ newState: NotchState) {
        guard newState != state else { return }
        state = newState
    }

    /// Body size of the expanded island for `content` — the one place the
    /// window and the SwiftUI drop both take it from. The settings are
    /// user-sized; the tour has a fixed, designed size.
    func panelSize(for content: IslandContent, settings: AppSettings) -> CGSize {
        switch content {
        case .settings: settings.expandedPanelSize
        case .onboarding: NotchMetrics.onboardingSize
        }
    }
}
