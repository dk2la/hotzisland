import Foundation

/// Tabs of the expanded island panel.
enum NotchTab: String, CaseIterable, Identifiable {
    case devices
    case media
    case calendar
    case metrics

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .devices: "laptopcomputer"
        case .media: "music.note"
        case .calendar: "calendar"
        case .metrics: "gauge"
        }
    }

    var title: String {
        switch self {
        case .devices: "Devices"
        case .media: "Media"
        case .calendar: "Calendar"
        case .metrics: "System"
        }
    }
}
