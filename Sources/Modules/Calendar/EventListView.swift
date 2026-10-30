import AppKit
import SwiftUI

/// The week of the selected day: a strip of seven day tiles, then that
/// day's events as one grouped card with start and end stacked, closed by
/// a "New event at 17:00" row. The next joinable event gets an accent
/// countdown in plain words ("in 12 min", "now") and a Join button when it
/// has a meeting link. "Now" is read from a `TimelineView` so the countdown
/// keeps ticking while the panel is open.
struct WeekView: View {
    var service: CalendarService

    private var calendar: Calendar { service.calendar }

    private var days: [Date] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: service.selectedDay) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let events = service.events(forDay: service.selectedDay)
            let nextID = calendar.isDateInToday(service.selectedDay)
                ? EventRow.next(in: events, at: context.date)?.id
                : nil
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    weekNav
                    HStack(spacing: 6) {
                        ForEach(days, id: \.self) { day in
                            dayTile(day, now: context.date)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: sectionTitle, trailing: events.isEmpty ? nil : "\(events.count)")
                            .padding(.top, 6)
                        GroupedCard {
                            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                                EventRow(
                                    event: event,
                                    isNext: event.id == nextID,
                                    isLast: index == events.count - 1 && !canCreate,
                                    stacked: true,
                                    now: context.date
                                ) {
                                    service.open(event)
                                }
                            }
                            if canCreate {
                                newEventRow
                            } else if events.isEmpty {
                                Text(L10n.t(.calNoEvents).prefix(1).uppercased() + L10n.t(.calNoEvents).dropFirst())
                                    .font(Theme.bodyFont)
                                    .foregroundStyle(Theme.textTertiary)
                                    .groupedRow(isLast: true)
                            }
                        }
                    }
                }
            }
        }
    }

    /// "26 Oct – 1 Nov" between the week arrows; the range jumps back to
    /// today.
    private var weekNav: some View {
        HStack(spacing: 2) {
            Button {
                service.goToToday()
            } label: {
                Text(rangeTitle)
                    .font(Theme.bodyFont)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            Spacer(minLength: 0)
            HeaderIconButton("chevron.left") { step(weeks: -1) }
            HeaderIconButton("chevron.right") { step(weeks: 1) }
        }
        .padding(.leading, 4)
    }

    private func step(weeks: Int) {
        guard let day = calendar.date(byAdding: .day, value: 7 * weeks, to: service.selectedDay) else { return }
        service.select(day: day)
    }

    private var rangeTitle: String {
        guard let first = days.first, let last = days.last else { return "" }
        return "\(Self.rangeFormatter.string(from: first)) – \(Self.rangeFormatter.string(from: last))"
    }

    /// "Today · Tue 27 Oct", or just the date further out.
    private var sectionTitle: String {
        let date = CalendarService.dayFormatter.string(from: service.selectedDay)
        let label = service.dayLabel(service.selectedDay)
        return label == date ? date : "\(label) · \(date)"
    }

    /// Weekday, number, up to three event dots. The selected day is the
    /// light tile; today keeps an accent numeral when another day is picked.
    private func dayTile(_ day: Date, now: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: service.selectedDay)
        let isToday = calendar.isDateInToday(day)
        let isPast = day < calendar.startOfDay(for: now)
        let count = service.events(forDay: day).count
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        let numeral: Color = isSelected ? Theme.inkOnAccent
            : isToday ? Theme.accent
            : isPast ? Theme.textTertiary
            : Theme.textPrimary
        return Button {
            service.select(day: day)
        } label: {
            VStack(spacing: 4) {
                Text(Self.weekdayFormatter.string(from: day))
                    .font(Theme.captionFont)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Theme.inkOnAccent.opacity(0.65) : Theme.textTertiary)
                Text("\(calendar.component(.day, from: day))")
                    .font(Theme.titleFont)
                    .monospacedDigit()
                    .foregroundStyle(numeral)
                HStack(spacing: 3) {
                    ForEach(0..<min(count, 3), id: \.self) { _ in
                        Circle()
                            .fill(isSelected ? Theme.inkOnAccent : isPast ? Theme.textQuaternary : Theme.textSecondary)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(shape.fill(isSelected ? Theme.lightFill : Theme.cardFill))
            .overlay(shape.stroke(Theme.hairlineSoft, lineWidth: isSelected ? 0 : 1))
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
    }

    private var canCreate: Bool { !service.writableCalendars.isEmpty }

    /// Dashed "+" and the slot the new event will take — the same one the
    /// form opens with (next full hour today, 09:00 otherwise).
    private var newEventRow: some View {
        Button {
            service.startCreating(on: service.selectedDay)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle().stroke(Theme.dashedBorder, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    )
                    .frame(width: 42, alignment: .leading)
                Text(L10n.f(.calNewEventAt, Self.slotLabel(on: service.selectedDay, calendar: calendar)))
                    .font(Theme.bodyFont)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .groupedRow(isLast: true)
        }
        .buttonStyle(PressableStyle())
    }

    private static func slotLabel(on day: Date, calendar: Calendar) -> String {
        let draft = EventDraft.new(on: day, calendarIdentifier: "", calendar: calendar)
        return EventRow.time(draft.start)
    }

    private static let weekdayFormatter = DateFormatter(template: "EEE")
    private static let rangeFormatter = DateFormatter(template: "d MMM")
}

/// The coming week as one rolling list: the next meeting as a hero card,
/// then TODAY / TOMORROW / FRI 4 SEP sections. Answers "when is my next
/// meeting" the moment the tab opens.
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

    private func todayEvents(in sections: [(day: Date, events: [CalendarEvent])]) -> [CalendarEvent] {
        guard let today = sections.first, service.calendar.isDateInToday(today.day) else { return [] }
        return today.events
    }

    var body: some View {
        let shown = sections
        if shown.isEmpty {
            EmptyStateZone(label: L10n.t(.calNoEvents))
                .frame(maxHeight: 90)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let today = todayEvents(in: shown)
                let nextID = EventRow.next(in: today, at: context.date)?.id
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if let upNext = UpNextCard.event(in: today, at: context.date) {
                            UpNextCard(event: upNext, now: context.date) {
                                service.open(upNext)
                            }
                        }
                        ForEach(shown, id: \.day) { day, events in
                            VStack(alignment: .leading, spacing: 8) {
                                SectionHeader(title: service.dayLabel(day), trailing: "\(events.count)")
                                EventGroup(events: events, nextID: nextID, now: context.date, onOpen: service.open)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// The rest of today's first timed event that has not ended: when, where,
/// who, how long until — and Join right on the card.
private struct UpNextCard: View {
    let event: CalendarEvent
    let now: Date
    let onOpen: () -> Void

    static func event(in events: [CalendarEvent], at now: Date) -> CalendarEvent? {
        events.first { !$0.isAllDay && $0.end > now }
    }

    private var guests: [String] {
        event.attendees.filter { !$0.isCurrentUser }.map(\.displayName)
    }

    var body: some View {
        Button(action: onOpen) {
            HeroCard {
                HStack(spacing: 7) {
                    StatusDot()
                    Text(L10n.t(.calUpNext))
                        .heroCaption()
                    Spacer(minLength: 0)
                    Text("\(EventRow.time(event.start)) – \(EventRow.time(event.end))")
                        .font(Theme.subFont)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(Theme.heroFont)
                            .lineLimit(2)
                            .foregroundStyle(Theme.textPrimary)
                        if let place = place {
                            Text(place)
                                .font(Theme.subFont)
                                .lineLimit(1)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    CountdownText(text: EventRow.countdown(to: event, at: now))
                }
                if !guests.isEmpty || event.joinURL != nil {
                    HStack(spacing: 10) {
                        if !guests.isEmpty {
                            AvatarStack(names: guests)
                        }
                        Spacer(minLength: 0)
                        if let url = event.joinURL {
                            ModuleButton(label: L10n.t(.calJoin), systemName: "video.fill", kind: .accent, height: 34) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    /// The location, else the calendar it lives in.
    private var place: String? {
        if let location = event.location, !location.isEmpty { return location }
        return event.calendarTitle.isEmpty ? nil : event.calendarTitle
    }
}

/// One day's events in a single grouped card.
private struct EventGroup: View {
    let events: [CalendarEvent]
    let nextID: String?
    let now: Date
    let onOpen: (CalendarEvent) -> Void

    var body: some View {
        GroupedCard {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                EventRow(
                    event: event,
                    isNext: event.id == nextID,
                    isLast: index == events.count - 1,
                    now: now
                ) {
                    onOpen(event)
                }
            }
        }
    }
}

/// One event row of a grouped card. Clicking the row opens the detail; the
/// Join button on the next meeting joins it directly. `now` comes from the
/// enclosing `TimelineView` so the countdown re-renders without a `Date()`
/// read.
struct EventRow: View {
    let event: CalendarEvent
    let isNext: Bool
    var isLast = false
    /// The week view's layout: start over end in the time column, no
    /// colour bar, place under the title.
    var stacked = false
    let now: Date
    let onOpen: () -> Void

    /// The row worth highlighting: upcoming-or-ongoing and close (≤2h).
    static func next(in events: [CalendarEvent], at now: Date) -> CalendarEvent? {
        events.first { event in
            guard !event.isAllDay, event.end > now else { return false }
            return event.start.timeIntervalSince(now) <= 2 * 3600
        }
    }

    /// "in 12 min", "in 1h 05m" or "now".
    static func countdown(to event: CalendarEvent, at now: Date) -> String {
        if event.start <= now { return L10n.t(.calNow) }
        let minutes = max(0, Int(event.start.timeIntervalSince(now) / 60))
        if minutes < 60 { return L10n.f(.calStartsInMinutes, minutes) }
        return L10n.f(.calStartsInHours, minutes / 60, minutes % 60)
    }

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private var isPast: Bool { event.end <= now }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.isAllDay ? "—" : Self.time(event.start))
                        .font(Theme.bodyFont)
                        .fontWeight(isNext ? .medium : .regular)
                        .foregroundStyle(isPast ? Theme.textQuaternary : isNext ? Theme.textPrimary : Theme.textSecondary)
                    if stacked, !event.isAllDay {
                        Text(Self.time(event.end))
                            .font(Theme.bodyFont)
                            .foregroundStyle(isPast ? Theme.textQuaternary : Theme.textTertiary)
                    }
                }
                .monospacedDigit()
                .frame(width: 42, alignment: .leading)
                if !stacked {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(event.color.opacity(isPast ? 0.45 : 1))
                        .frame(width: 3, height: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(Theme.bodyFont)
                        .fontWeight(isNext ? .semibold : .medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(isPast ? Theme.textTertiary : Theme.textPrimary)
                    Text(subtitle)
                        .font(Theme.subFont)
                        .lineLimit(1)
                        .foregroundStyle(isNext ? Theme.accent : Theme.textTertiary)
                }
                Spacer(minLength: 0)
                if isNext, let url = event.joinURL {
                    ModuleButton(label: L10n.t(.calJoin), kind: .accent, height: 26) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .groupedRow(isLast: isLast)
        }
        .buttonStyle(PressableStyle())
    }

    /// The countdown for the highlighted row, "All day", else
    /// "30m · Room 4".
    private var subtitle: String {
        if isNext { return Self.countdown(to: event, at: now) }
        if event.isAllDay { return L10n.t(.calAllDay) }
        if stacked {
            if let location = event.location, !location.isEmpty { return location }
            return event.calendarTitle
        }
        let minutes = Int(event.end.timeIntervalSince(event.start) / 60)
        let duration = minutes >= 60 ? String(format: "%dh%02d", minutes / 60, minutes % 60) : "\(minutes)m"
        if let location = event.location, !location.isEmpty {
            return "\(duration) · \(location)"
        }
        return duration
    }

    private static let timeFormatter = DateFormatter(format: "HH:mm")
}
