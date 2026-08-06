import SwiftUI

/// Layout of the calendar tab.
enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    /// Month grid plus the selected day's events beside it.
    case gridAndList
    /// Only events, with day-by-day navigation.
    case listOnly
    /// Only the month grid.
    case gridOnly

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .gridAndList: "rectangle.split.2x1"
        case .listOnly: "list.bullet"
        case .gridOnly: "calendar"
        }
    }

    var showsGrid: Bool { self != .listOnly }
    var showsList: Bool { self != .gridOnly }
}

/// A calendar available in the system (iCloud, Google, Exchange, …).
struct CalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    /// Account the calendar belongs to — "iCloud", "Google", …
    let sourceTitle: String
    let color: Color
}

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    /// Meeting link extracted from the event's URL or notes, if any.
    let joinURL: URL?
}
