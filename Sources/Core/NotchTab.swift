import Foundation
import SwiftUI

/// Modules of the panel — V3 set. Six ship enabled by default, four are
/// optional; everything is replaceable in settings. Email, Notes and Chats
/// are placeholders until their services land.
enum NotchTab: String, CaseIterable, Identifiable {
    case playbooks
    case calendar
    case email
    case clipboard
    case notes
    case chats
    case media
    case timer
    case shelf
    case metrics

    var id: String { rawValue }

    /// Modules enabled out of the box (still toggleable).
    static let defaultTabs: [NotchTab] = [.playbooks, .calendar, .email, .clipboard, .notes, .chats]
    /// Modules the user opts into from settings.
    static let optionalTabs: [NotchTab] = [.media, .timer, .shelf, .metrics]
    /// No backing service yet — shown as "soon", excluded from defaults.
    static let comingSoon: Set<NotchTab> = [.chats]

    var isComingSoon: Bool { Self.comingSoon.contains(self) }

    /// Short label (compact chrome).
    var channelLabel: String {
        switch self {
        case .playbooks: "Play"
        case .calendar: "Cal"
        case .email: "Mail"
        case .clipboard: "Clip"
        case .notes: "Notes"
        case .chats: "Chats"
        case .media: "Media"
        case .timer: "Timer"
        case .shelf: "Shelf"
        case .metrics: "Sys"
        }
    }

    /// Full localized name for headers and the settings window.
    @MainActor
    var title: String {
        switch self {
        case .playbooks: L10n.t(.modPlaybooks)
        case .calendar: L10n.t(.modCalendar)
        case .email: L10n.t(.modEmail)
        case .clipboard: L10n.t(.modClipboard)
        case .notes: L10n.t(.modNotes)
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
        case .chats: "bubble.left"
        case .media: "music.note"
        case .timer: "timer"
        case .shelf: "tray"
        case .metrics: "gauge"
        }
    }
}
