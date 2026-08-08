import Foundation

/// Tabs of the expanded island panel.
enum NotchTab: String, CaseIterable, Identifiable {
    case playbooks
    case devices
    case media
    case calendar
    case metrics
    case shelf
    case clipboard
    case timer

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .playbooks: "bolt.fill"
        case .devices: "laptopcomputer"
        case .media: "music.note"
        case .calendar: "calendar"
        case .metrics: "gauge"
        case .shelf: "tray"
        case .clipboard: "doc.on.clipboard"
        case .timer: "timer"
        }
    }

    var title: String {
        switch self {
        case .playbooks: "Playbooks"
        case .devices: "Devices"
        case .media: "Media"
        case .calendar: "Calendar"
        case .metrics: "System"
        case .shelf: "Shelf"
        case .clipboard: "Clipboard"
        case .timer: "Timer"
        }
    }
}
