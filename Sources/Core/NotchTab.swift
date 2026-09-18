import Foundation
import SwiftUI

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

    /// Full localized name for headers and the settings window.
    @MainActor
    var title: String {
        switch self {
        case .playbooks: L10n.t(.modPlaybooks)
        case .calendar: L10n.t(.modCalendar)
        case .email: L10n.t(.modEmail)
        case .clipboard: L10n.t(.modClipboard)
        case .notes: L10n.t(.modNotes)
        case .assistant: L10n.t(.modAssistant)
        case .chats: L10n.t(.modChats)
        case .media: L10n.t(.modMusic)
        case .timer: L10n.t(.modTimer)
        case .shelf: L10n.t(.modShelf)
        case .metrics: L10n.t(.modSystem)
        }
    }

    var icon: String {
        switch self {
        case .playbooks: "bolt.fill"
        case .calendar: "calendar"
        case .email: "envelope"
        case .clipboard: "doc.on.clipboard"
        case .notes: "note.text"
        case .assistant: "sparkles"
        case .chats: "bubble.left"
        case .media: "music.note"
        case .timer: "timer"
        case .shelf: "tray"
        case .metrics: "gauge"
        }
    }
}
