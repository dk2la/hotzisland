/// Pages of the welcome tour, in order. Module pages wear their module's
/// own name, as the widget's panel header does.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case calendar
    case mail
    case playbooks
    case notes
    case assistant
    case ready

    var id: Int { rawValue }

    /// The module the page presents, if any.
    var tab: ModuleTab? {
        switch self {
        case .calendar: .calendar
        case .mail: .email
        case .playbooks: .playbooks
        case .notes: .notes
        case .assistant: .assistant
        case .welcome, .ready: nil
        }
    }

    /// The stage panel's header — the module name, as on the widget.
    @MainActor var panelTitle: String {
        switch self {
        case .welcome: L10n.t(.obWelcomeKicker)
        case .ready: L10n.t(.obReadyKicker)
        default: tab?.title ?? ""
        }
    }

    @MainActor var title: String {
        switch self {
        case .welcome: "Pocket"
        case .calendar: L10n.t(.obCalendarTitle)
        case .mail: L10n.t(.obMailTitle)
        case .playbooks: L10n.t(.obPlaybooksTitle)
        case .notes: L10n.t(.obNotesTitle)
        case .assistant: L10n.t(.obAssistantTitle)
        case .ready: L10n.t(.obFinishTitle)
        }
    }

    @MainActor var body: String {
        switch self {
        case .welcome: L10n.t(.obWelcomeBody)
        case .calendar: L10n.t(.obCalendarBody)
        case .mail: L10n.t(.obMailBody)
        case .playbooks: L10n.t(.obPlaybooksBody)
        case .notes: L10n.t(.obNotesBody)
        case .assistant: L10n.t(.obAssistantBody)
        case .ready: L10n.t(.obFinishBody)
        }
    }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    var isLast: Bool { next == nil }
}
