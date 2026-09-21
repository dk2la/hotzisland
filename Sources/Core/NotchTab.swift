/// Modules of the panel — V3 set. Every module except the coming-soon ones
/// ships enabled (see AppSettings); all are toggleable and reorderable in
/// settings. Only Chats is still a placeholder without a backing service.
enum NotchTab: String, CaseIterable, Identifiable {
    case playbooks
    case calendar
    case email
    case clipboard
    case notes
    case assistant
    case chats
    case media
    case timer
    case shelf
    case metrics

    var id: String { rawValue }

    /// Core module set — tagged "default" in the settings module list. Not
    /// the enabled-by-default set (AppSettings enables everything that is
    /// not coming soon); it only drives the badge.
    static let defaultTabs: [NotchTab] = [.playbooks, .calendar, .email, .clipboard, .notes, .assistant, .chats]
    /// No backing service yet — shown as "soon", excluded from defaults.
    static let comingSoon: Set<NotchTab> = [.chats]

    var isComingSoon: Bool { Self.comingSoon.contains(self) }

    private var spec: (title: L10nKey, icon: String) {
        switch self {
        case .playbooks: (.modPlaybooks, "bolt.fill")
        case .calendar: (.modCalendar, "calendar")
        case .email: (.modEmail, "envelope")
        case .clipboard: (.modClipboard, "doc.on.clipboard")
        case .notes: (.modNotes, "note.text")
        case .assistant: (.modAssistant, "sparkles")
        case .chats: (.modChats, "bubble.left")
        case .media: (.modMusic, "music.note")
        case .timer: (.modTimer, "timer")
        case .shelf: (.modShelf, "tray")
        case .metrics: (.modSystem, "gauge")
        }
    }

    /// Full localized name for headers and the settings window.
    @MainActor var title: String { L10n.t(spec.title) }
    var icon: String { spec.icon }
}
