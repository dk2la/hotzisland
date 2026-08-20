import Foundation

/// Channels of the expanded island panel. Per the Instrument DS, battery
/// and audio live inside Sys — there is no separate Devices tab.
enum NotchTab: String, CaseIterable, Identifiable {
    case playbooks
    case media
    case calendar
    case metrics
    case shelf
    case clipboard
    case timer

    var id: String { rawValue }

    /// Channel-selector label (mono caps row on top of the panel).
    var channelLabel: String {
        switch self {
        case .playbooks: "Play"
        case .media: "Media"
        case .calendar: "Cal"
        case .metrics: "Sys"
        case .shelf: "Shelf"
        case .clipboard: "Clip"
        case .timer: "Timer"
        }
    }

    /// Full name for the settings window.
    var title: String {
        switch self {
        case .playbooks: "Playbooks"
        case .media: "Media"
        case .calendar: "Calendar"
        case .metrics: "System"
        case .shelf: "Shelf"
        case .clipboard: "Clipboard"
        case .timer: "Timer"
        }
    }

    var icon: String {
        switch self {
        case .playbooks: "bolt.fill"
        case .media: "music.note"
        case .calendar: "calendar"
        case .metrics: "gauge"
        case .shelf: "tray"
        case .clipboard: "doc.on.clipboard"
        case .timer: "timer"
        }
    }
}
