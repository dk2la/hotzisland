import AppKit
import SwiftUI

/// Events of the selected day as data registers: mono time column, title,
/// mono annotation on the right, hairline separators. The next joinable
/// event gets an accent countdown in plain words ("in 12 min", "now") and
/// a Join label when it has a meeting link. "Now" is read from a
/// `TimelineView` so the countdown keeps ticking while the panel is open.
struct EventListView: View {
    var service: CalendarService
    let day: Date

    private var events: [CalendarEvent] { service.events(forDay: day) }

    /// The first upcoming-or-ongoing event today. The countdown only lights
    /// up when it is close (≤2h) — "in 12h 55m" is noise, not a readout.
    private func nextEvent(at now: Date) -> CalendarEvent? {
        guard service.calendar.isDateInToday(day) else { return nil }
        return EventRow.next(in: events, at: now)
    }

    var body: some View {
        if events.isEmpty {
            EmptyStateZone(label: L10n.t(.calNoEvents))
                .frame(maxHeight: 90)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let nextEvent = nextEvent(at: context.date)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(events) { event in
                            EventRow(event: event, isNext: event.id == nextEvent?.id, now: context.date)
                            if event.id != events.last?.id {
                                Hairline()
                            }
                        }
                    }
                }
            }
        }
    }
}

/// The coming week as one rolling list — TODAY / TOMORROW / FRI 4 SEP
/// sections. Answers "when is my next meeting" the moment the tab opens.
struct AgendaListView: View {
    var service: CalendarService

    private var sections: [(day: Date, events: [CalendarEvent])] {
        let start = service.calendar.startOfDay(for: Date())
        return (0..<8).compactMap { offset in
            guard let day = service.calendar.date(byAdding: .day, value: offset, to: start)
            else { return nil }
            let events = service.events(forDay: day)
            return events.isEmpty ? nil : (day, events)
        }
    }

    private func nextEvent(at now: Date) -> CalendarEvent? {
        guard let today = sections.first, service.calendar.isDateInToday(today.day)
        else { return nil }
        return EventRow.next(in: today.events, at: now)
    }

    var body: some View {
        let shown = sections
        if shown.isEmpty {
            EmptyStateZone(label: L10n.t(.calNoEvents))
                .frame(maxHeight: 90)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let nextEvent = nextEvent(at: context.date)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(shown, id: \.day) { day, events in
                            // Accent, same register as the panel title — the day
                            // dividers must not read as just another event row.
                            InstrumentLabel(label(for: day), color: Theme.accent)
                                .padding(.top, day == shown.first?.day ? 0 : 12)
                                .padding(.bottom, 4)
                            ForEach(events) { event in
                                EventRow(event: event, isNext: event.id == nextEvent?.id, now: context.date)
                                if event.id != events.last?.id {
                                    Hairline()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func label(for day: Date) -> String {
        if service.calendar.isDateInToday(day) { return L10n.t(.calToday) }
        if service.calendar.isDateInTomorrow(day) { return L10n.t(.calTomorrow) }
        return Self.dayFormatter.string(from: day)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
    }()
}

/// One event register row, shared by the day list and the agenda. Clicking
/// an event with a meeting link joins it. `now` comes from the enclosing
/// `TimelineView` so the countdown re-renders without a `Date()` read.
struct EventRow: View {
    let event: CalendarEvent
    let isNext: Bool
    let now: Date

    /// The row worth highlighting: upcoming-or-ongoing and close (≤2h).
    static func next(in events: [CalendarEvent], at now: Date) -> CalendarEvent? {
        events.first { event in
            guard !event.isAllDay, event.end > now else { return false }
            return event.start.timeIntervalSince(now) <= 2 * 3600
        }
    }

    var body: some View {
        Button {
            if let url = event.joinURL {
                NSWorkspace.shared.open(url)
            }
        } label: {
            DataRow(
                leading: event.isAllDay ? "—" : Self.timeFormatter.string(from: event.start),
                title: event.title,
                titleColor: isNext ? Theme.textPrimary : Theme.textSecondary
            ) {
                HStack(spacing: 8) {
                    Text(annotation)
                        .font(Theme.readoutSFont)
                        .foregroundStyle(isNext ? Theme.accent : Theme.textQuaternary)
                    if isNext, event.joinURL != nil {
                        joinLabel
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    /// Countdown for the highlighted row ("in 12 min", "in 1h 05m", "now");
    /// duration for everyone else.
    private var annotation: String {
        if isNext {
            let minutes = max(0, Int(event.start.timeIntervalSince(now) / 60))
            if event.start <= now { return L10n.t(.calNow) }
            if minutes < 60 { return L10n.f(.calStartsInMinutes, minutes) }
            return L10n.f(.calStartsInHours, minutes / 60, minutes % 60)
        }
        if event.isAllDay { return L10n.t(.calAllDay) }
        let minutes = Int(event.end.timeIntervalSince(event.start) / 60)
        return minutes >= 60 ? String(format: "%dh%02d", minutes / 60, minutes % 60) : "\(minutes)m"
    }

    /// Small accent-bordered "Join" tag — the whole row is the button, the
    /// tag just says what the click does.
    private var joinLabel: some View {
        InstrumentLabel(L10n.t(.calJoin), color: Theme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                Capsule()
                    .stroke(Theme.accentBorder, lineWidth: 1)
            )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
