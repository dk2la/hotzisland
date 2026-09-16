import SwiftUI

/// Layout of the calendar tab.
enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    /// Month grid on top (at most a third of the panel), the selected
    /// day's events under it.
    case gridAndList
    /// The coming days as one rolling agenda.
    case listOnly

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .gridAndList: "calendar"
        case .listOnly: "list.bullet"
        }
    }

    var showsGrid: Bool { self != .listOnly }
}

/// A calendar available in the system (iCloud, Google, Exchange, …).
struct CalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    /// Account the calendar belongs to — "iCloud", "Google", …
    let sourceTitle: String
    let color: Color
}

struct CalendarEvent: Identifiable, Equatable, Sendable {
    /// One invitee, mapped from `EKParticipant`. Rows are keyed by position
    /// — two attendees can legitimately share a name and lack an email.
    struct Attendee: Equatable, Sendable {
        enum Status: Equatable, Sendable {
            case accepted, declined, tentative, pending, unknown
        }

        let name: String
        let email: String?
        let status: Status
        let isOrganizer: Bool
        let isCurrentUser: Bool

        /// What the row shows: the name, or the address when there is none.
        var displayName: String { name.isEmpty ? (email ?? "?") : name }
    }

    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    /// Meeting link extracted from the event's URL or notes, if any.
    let joinURL: URL?
    let location: String?
    let notes: String?
    /// The event's own URL field, untouched — `joinURL` may come from notes.
    let url: URL?
    let calendarTitle: String
    let calendarIdentifier: String
    let attendees: [Attendee]
    let organizerName: String?
    /// The calendar accepts changes and the event is ours — an invite from
    /// someone else can only be answered, not rewritten.
    let isEditable: Bool
    let eventIdentifier: String
}

/// Form values for a new or edited event. `id == nil` creates.
struct EventDraft: Equatable, Sendable {
    var id: String?
    var title = ""
    var calendarIdentifier: String
    var start: Date
    var end: Date
    var isAllDay = false
    var location = ""
    var notes = ""
    var url = ""

    /// A blank one-hour slot on `day`: the next full hour for today, 09:00
    /// for any other day.
    static func new(on day: Date, calendarIdentifier: String, calendar: Calendar) -> EventDraft {
        let dayStart = calendar.startOfDay(for: day)
        let start: Date
        if calendar.isDateInToday(day) {
            let now = Date()
            let hour = calendar.component(.hour, from: now)
            start = calendar.date(bySettingHour: min(hour + 1, 23), minute: 0, second: 0, of: now) ?? now
        } else {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart) ?? dayStart
        }
        return EventDraft(
            calendarIdentifier: calendarIdentifier,
            start: start,
            end: start.addingTimeInterval(3600)
        )
    }

    init(
        id: String? = nil,
        title: String = "",
        calendarIdentifier: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        location: String = "",
        notes: String = "",
        url: String = ""
    ) {
        self.id = id
        self.title = title
        self.calendarIdentifier = calendarIdentifier
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.url = url
    }

    /// Prefilled from an existing event. An all-day event's end is shown
    /// as its last day, not the midnight EventKit stores.
    init(event: CalendarEvent, calendar: Calendar) {
        self.init(
            id: event.eventIdentifier,
            title: event.title,
            calendarIdentifier: event.calendarIdentifier,
            start: event.start,
            end: event.isAllDay
                ? calendar.startOfDay(for: max(event.start, event.end - 1))
                : event.end,
            isAllDay: event.isAllDay,
            location: event.location ?? "",
            notes: event.notes ?? "",
            url: event.url?.absoluteString ?? ""
        )
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Title present and the range makes sense; an all-day event may start
    /// and end on the same day.
    var isValid: Bool {
        guard !trimmedTitle.isEmpty else { return false }
        return isAllDay ? end >= start : end > start
    }
}
