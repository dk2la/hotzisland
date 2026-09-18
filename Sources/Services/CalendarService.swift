import AppKit
import EventKit
import Observation
import OSLog
import SwiftUI

/// Reads events from every calendar configured in the system (iCloud, Google,
/// Exchange, …) through EventKit. Which calendars are shown and how they are
/// laid out is persisted between launches.
@MainActor
@Observable
final class CalendarService {
    enum Access: Equatable {
        case unknown
        case granted
        case denied
    }

    private(set) var access: Access = .unknown
    private(set) var calendars: [CalendarInfo] = []
    /// Events of the displayed month, grouped by day.
    private(set) var eventsByDay: [Date: [CalendarEvent]] = [:]

    /// Calendars the user picked. Empty means "all of them".
    private(set) var enabledCalendarIDs: Set<String> = []
    /// Agenda-first: the list is what answers "when is my next meeting";
    /// the grid stays one toggle away.
    private(set) var displayMode: CalendarDisplayMode = .listOnly
    /// Calendar-visibility picker, shown in place of the content. Lives here
    /// because the panel header owns the toggle.
    var showingPicker = false

    /// Event whose detail card is open — replaces the list.
    private(set) var selectedEvent: CalendarEvent?
    /// Event whose edit form is open; nil while creating or browsing.
    private(set) var editingEvent: CalendarEvent?
    /// The blank form for a new event is open.
    private(set) var isCreating = false
    /// Day the new event is proposed on.
    private(set) var creationDay: Date = Calendar.current.startOfDay(for: Date())
    /// A prefilled form handed over by the assistant; consumed by the next
    /// `newDraft()` so the editor opens with it instead of a blank draft.
    @ObservationIgnored var pendingDraft: EventDraft?
    /// Calendars that accept new and edited events, sorted by title.
    private(set) var writableCalendars: [CalendarInfo] = []
    /// Last save/delete failure, shown by the form and the detail card.
    var lastError: String?

    var displayedMonth: Date = Date()
    var selectedDay: Date = Calendar.current.startOfDay(for: Date())

    /// Demo mode: scripted calendars and events, EventKit untouched. Saves
    /// and deletes edit the scripted list so the forms work on camera.
    private(set) var isDemo = false
    @ObservationIgnored private var demoEvents: [CalendarEvent] = []
    /// What EventKit last answered — kept apart from `access` so the demo
    /// can claim access without losing the real answer.
    @ObservationIgnored private var realAccess: Access = .unknown
    @ObservationIgnored private var parkedEnabledIDs: Set<String> = []

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "calendar")
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private static let enabledKey = "calendar.enabledIDs"
    @ObservationIgnored private static let modeKey = "calendar.displayMode"

    /// Monday-first calendar, matching the rest of the UI.
    @ObservationIgnored private(set) var calendar: Calendar = {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }()

    init() {
        if let stored = defaults.array(forKey: Self.enabledKey) as? [String] {
            enabledCalendarIDs = Set(stored)
        }
        if let raw = defaults.string(forKey: Self.modeKey),
           let mode = CalendarDisplayMode(rawValue: raw) {
            displayMode = mode
        }

        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }

        Task { await requestAccess() }
    }

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            realAccess = granted ? .granted : .denied
        } catch {
            realAccess = .denied
        }
        log.info("calendar access: \(String(describing: self.realAccess), privacy: .public)")
        // The answer may land while the demo is on; it applies on exit.
        guard !isDemo else { return }
        access = realAccess
        if access == .granted { reload() }
    }

    // MARK: - Settings

    func setDisplayMode(_ mode: CalendarDisplayMode) {
        displayMode = mode
        defaults.set(mode.rawValue, forKey: Self.modeKey)
        // The agenda always starts from now; a month browsed in grid mode
        // would otherwise leave it staring at unloaded days.
        if mode == .listOnly {
            goToToday()
        }
    }

    func isEnabled(_ calendarID: String) -> Bool {
        enabledCalendarIDs.isEmpty || enabledCalendarIDs.contains(calendarID)
    }

    func toggleCalendar(_ calendarID: String) {
        // An empty set means "everything"; materialise it before excluding.
        if enabledCalendarIDs.isEmpty {
            enabledCalendarIDs = Set(calendars.map(\.id))
        }
        if enabledCalendarIDs.contains(calendarID) {
            enabledCalendarIDs.remove(calendarID)
        } else {
            enabledCalendarIDs.insert(calendarID)
        }
        if !isDemo {
            defaults.set(Array(enabledCalendarIDs), forKey: Self.enabledKey)
        }
        reload()
    }

    // MARK: - Navigation

    func step(months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: displayedMonth) else { return }
        displayedMonth = next
        reload()
    }

    func step(days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: selectedDay) else { return }
        select(day: next)
    }

    func select(day: Date) {
        selectedDay = calendar.startOfDay(for: day)
        if !calendar.isDate(selectedDay, equalTo: displayedMonth, toGranularity: .month) {
            displayedMonth = selectedDay
            reload()
        }
    }

    func goToToday() {
        displayedMonth = Date()
        select(day: Date())
        reload()
    }

    func events(forDay day: Date) -> [CalendarEvent] {
        eventsByDay[calendar.startOfDay(for: day)] ?? []
    }

    func hasEvents(on day: Date) -> Bool {
        !(eventsByDay[calendar.startOfDay(for: day)] ?? []).isEmpty
    }

    // MARK: - Detail, create, edit

    func open(_ event: CalendarEvent) {
        lastError = nil
        showingPicker = false
        selectedEvent = event
    }

    func closeEvent() {
        selectedEvent = nil
        editingEvent = nil
        lastError = nil
    }

    func startCreating(on day: Date) {
        guard access == .granted, !writableCalendars.isEmpty else { return }
        lastError = nil
        showingPicker = false
        creationDay = calendar.startOfDay(for: day)
        isCreating = true
    }

    func cancelCreating() {
        isCreating = false
        lastError = nil
    }

    func startEditing(_ event: CalendarEvent) {
        guard event.isEditable else { return }
        lastError = nil
        editingEvent = event
    }

    func cancelEditing() {
        editingEvent = nil
        lastError = nil
    }

    /// Calendar new events land in unless the user picks another one.
    var defaultCalendarIdentifier: String? {
        if isDemo { return writableCalendars.first?.id }
        if let preferred = store.defaultCalendarForNewEvents,
           preferred.allowsContentModifications {
            return preferred.calendarIdentifier
        }
        return writableCalendars.first?.id
    }

    /// Blank form for `creationDay` on the default calendar — or the draft
    /// the assistant prepared, once.
    func newDraft() -> EventDraft {
        if let pending = pendingDraft {
            pendingDraft = nil
            return pending
        }
        return EventDraft.new(
            on: creationDay,
            calendarIdentifier: defaultCalendarIdentifier ?? "",
            calendar: calendar
        )
    }

    /// Writes the form into EventKit — a fresh `EKEvent` for a new one, the
    /// stored event for an edit — and shows the result's detail card. The
    /// month is reloaded so lists and dots catch up.
    func save(draft: EventDraft) throws {
        if isDemo {
            saveDemo(draft: draft)
            return
        }
        let event: EKEvent
        if let id = draft.id {
            guard let existing = store.event(withIdentifier: id) else {
                throw CalendarError.eventNotFound
            }
            event = existing
        } else {
            event = EKEvent(eventStore: store)
        }
        // Only a writable calendar may be chosen; an edited event keeps its
        // calendar when the picked one has vanished.
        if let picked = store.calendar(withIdentifier: draft.calendarIdentifier),
           picked.allowsContentModifications {
            event.calendar = picked
        } else if draft.id == nil {
            guard let fallback = store.defaultCalendarForNewEvents,
                  fallback.allowsContentModifications
            else { throw CalendarError.noWritableCalendar }
            event.calendar = fallback
        }
        event.title = draft.trimmedTitle
        event.isAllDay = draft.isAllDay
        if draft.isAllDay {
            // All-day spans whole days: midnight to the last second of the
            // last day, which is how Calendar.app stores them.
            let first = calendar.startOfDay(for: draft.start)
            let last = calendar.startOfDay(for: max(draft.start, draft.end))
            event.startDate = first
            event.endDate = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: last) ?? last
        } else {
            event.startDate = draft.start
            event.endDate = draft.end
        }
        let location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        event.location = location.isEmpty ? nil : location
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        event.notes = notes.isEmpty ? nil : notes
        let urlText = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        event.url = urlText.isEmpty ? nil : URL(string: urlText)

        try store.save(event, span: .thisEvent, commit: true)
        log.info("saved event \(event.eventIdentifier ?? "?", privacy: .public) new=\(draft.id == nil, privacy: .public)")

        lastError = nil
        isCreating = false
        editingEvent = nil
        selectedEvent = makeEvent(from: event)
        reload()
    }

    /// Removes this occurrence only; the detail card closes with it.
    func delete(_ event: CalendarEvent) throws {
        if isDemo {
            demoEvents.removeAll { $0.id == event.id }
            lastError = nil
            if selectedEvent?.id == event.id { closeEvent() }
            reload()
            return
        }
        guard let stored = store.event(withIdentifier: event.eventIdentifier) else {
            throw CalendarError.eventNotFound
        }
        try store.remove(stored, span: .thisEvent, commit: true)
        log.info("deleted event \(event.eventIdentifier, privacy: .public)")
        lastError = nil
        if selectedEvent?.id == event.id { closeEvent() }
        reload()
    }

    /// Hands the event to Calendar.app. EventKit cannot add invitees on
    /// macOS, so that is where attendees get managed.
    func openInCalendarApp(_ event: CalendarEvent) {
        let identifier = event.eventIdentifier
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? event.eventIdentifier
        guard let url = URL(string: "ical://ekevent/\(identifier)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Loading

    func reload() {
        if isDemo {
            reloadDemo()
            return
        }
        guard access == .granted else { return }

        let ekCalendars = store.calendars(for: .event)
        calendars = ekCalendars.map { calendar in
            CalendarInfo(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                sourceTitle: calendar.source?.title ?? "Local",
                color: Color(nsColor: calendar.color ?? .systemBlue)
            )
        }
        .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
        writableCalendars = ekCalendars
            .filter(\.allowsContentModifications)
            .map { calendar in
                CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source?.title ?? "Local",
                    color: Color(nsColor: calendar.color ?? .systemBlue)
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let active = ekCalendars.filter { isEnabled($0.calendarIdentifier) }
        guard !active.isEmpty,
              let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              // Pad by a week on both sides so leading/trailing grid days
              // also show their event dots.
              let rangeStart = calendar.date(byAdding: .day, value: -7, to: monthInterval.start),
              let rangeEnd = calendar.date(byAdding: .day, value: 7, to: monthInterval.end)
        else {
            eventsByDay = [:]
            return
        }

        let predicate = store.predicateForEvents(withStart: rangeStart, end: rangeEnd, calendars: active)
        var events: [CalendarEvent] = []
        // The same meeting often exists in several calendars (work Exchange +
        // Google invite) — deduplicate by title and exact time.
        var seen = Set<String>()
        for event in store.events(matching: predicate) {
            guard let start = event.startDate else { continue }
            let dedupKey = "\(event.title ?? "")|\(start.timeIntervalSince1970)|\(event.endDate?.timeIntervalSince1970 ?? 0)"
            guard seen.insert(dedupKey).inserted else { continue }
            events.append(makeEvent(from: event))
        }
        let grouped = group(events, from: rangeStart, to: rangeEnd)
        eventsByDay = grouped
        // An open detail card follows external edits; a vanished event
        // keeps its last known values until the user closes it.
        if let open = selectedEvent,
           let fresh = grouped.values.lazy.flatMap({ $0 }).first(where: { $0.id == open.id }) {
            selectedEvent = fresh
        }
        log.info("""
        loaded calendars=\(self.calendars.count, privacy: .public) \
        sources=\(Set(self.calendars.map(\.sourceTitle)).sorted().joined(separator: ","), privacy: .public) \
        active=\(active.count, privacy: .public) \
        days=\(grouped.count, privacy: .public) \
        events=\(grouped.values.map(\.count).reduce(0, +), privacy: .public)
        """)
    }

    /// Events by the days they cover, each day's list sorted all-day first.
    /// A multi-day event belongs to every day it covers. The last day is
    /// the one containing (end − 1s): an event ending exactly at midnight —
    /// which is how EventKit ends all-day events — must not spill onto the
    /// next day. Clipped to the loaded window so a months-long event does
    /// not register hundreds of days.
    private func group(_ events: [CalendarEvent], from rangeStart: Date, to rangeEnd: Date) -> [Date: [CalendarEvent]] {
        var grouped: [Date: [CalendarEvent]] = [:]
        for event in events {
            var day = max(calendar.startOfDay(for: event.start), rangeStart)
            let lastDay = min(calendar.startOfDay(for: max(event.start, event.end - 1)), rangeEnd)
            while day <= lastDay {
                grouped[day, default: []].append(event)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        for (day, events) in grouped {
            grouped[day] = events.sorted { lhs, rhs in
                lhs.isAllDay == rhs.isAllDay ? lhs.start < rhs.start : lhs.isAllDay
            }
        }
        return grouped
    }

    // MARK: - Demo mode

    /// Shows scripted calendars as a fully granted account. The real
    /// calendar choice is parked; EventKit keeps answering in the background.
    func enterDemo(calendars demoCalendars: [CalendarInfo], events: [CalendarEvent]) {
        guard !isDemo else { return }
        isDemo = true
        parkedEnabledIDs = enabledCalendarIDs
        enabledCalendarIDs = []
        demoEvents = events
        access = .granted
        calendars = demoCalendars
        writableCalendars = demoCalendars
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        selectedEvent = nil
        editingEvent = nil
        isCreating = false
        showingPicker = false
        lastError = nil
        goToToday()
    }

    func exitDemo() {
        guard isDemo else { return }
        isDemo = false
        demoEvents = []
        enabledCalendarIDs = parkedEnabledIDs
        selectedEvent = nil
        editingEvent = nil
        isCreating = false
        showingPicker = false
        lastError = nil
        access = realAccess
        calendars = []
        writableCalendars = []
        eventsByDay = [:]
        goToToday()
    }

    /// The scripted events of the displayed month, filtered like the real
    /// ones by the calendar picker.
    private func reloadDemo() {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let rangeStart = calendar.date(byAdding: .day, value: -7, to: monthInterval.start),
              let rangeEnd = calendar.date(byAdding: .day, value: 7, to: monthInterval.end)
        else {
            eventsByDay = [:]
            return
        }
        let visible = demoEvents.filter {
            isEnabled($0.calendarIdentifier) && $0.end > rangeStart && $0.start < rangeEnd
        }
        let grouped = group(visible, from: rangeStart, to: rangeEnd)
        eventsByDay = grouped
        if let open = selectedEvent,
           let fresh = grouped.values.lazy.flatMap({ $0 }).first(where: { $0.id == open.id }) {
            selectedEvent = fresh
        }
    }

    /// Writes the form into the scripted list — a new event or an edit in
    /// place — and shows its detail card, like the EventKit path.
    private func saveDemo(draft: EventDraft) {
        let info = calendars.first { $0.id == draft.calendarIdentifier } ?? writableCalendars.first
        let existing = draft.id.flatMap { id in demoEvents.first { $0.eventIdentifier == id } }
        let id = existing?.id ?? "demo.event.\(UUID().uuidString)"
        let start: Date
        let end: Date
        if draft.isAllDay {
            let first = calendar.startOfDay(for: draft.start)
            let last = calendar.startOfDay(for: max(draft.start, draft.end))
            start = first
            end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: last) ?? last
        } else {
            start = draft.start
            end = draft.end
        }
        let location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlText = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = urlText.isEmpty ? nil : URL(string: urlText)
        let event = CalendarEvent(
            id: id,
            title: draft.trimmedTitle,
            start: start,
            end: end,
            isAllDay: draft.isAllDay,
            color: info?.color ?? .blue,
            joinURL: url?.scheme?.hasPrefix("http") == true ? url : existing?.joinURL,
            location: location.isEmpty ? nil : location,
            notes: notes.isEmpty ? nil : notes,
            url: url,
            calendarTitle: info?.title ?? "",
            calendarIdentifier: info?.id ?? "",
            attendees: existing?.attendees ?? [],
            organizerName: existing?.organizerName,
            isEditable: true,
            eventIdentifier: id
        )
        demoEvents.removeAll { $0.id == id }
        demoEvents.append(event)
        lastError = nil
        isCreating = false
        editingEvent = nil
        selectedEvent = event
        reload()
    }

    /// Snapshot of an `EKEvent` as a plain value — built here, on the main
    /// actor, so views never touch EventKit objects.
    private func makeEvent(from event: EKEvent) -> CalendarEvent {
        let start = event.startDate ?? Date()
        let organizer = event.organizer
        let attendees = (event.attendees ?? []).map { participant in
            Self.attendee(from: participant, organizer: organizer)
        }
        // Someone else's invite is answered, not rewritten — Calendar.app
        // refuses the edit too.
        let isOwn = organizer == nil || organizer?.isCurrentUser == true
        return CalendarEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "(No title)",
            start: start,
            end: event.endDate ?? start,
            isAllDay: event.isAllDay,
            color: Color(nsColor: event.calendar.color ?? .systemBlue),
            joinURL: Self.meetingURL(for: event),
            location: Self.nonEmpty(event.location),
            notes: Self.nonEmpty(event.notes),
            url: event.url,
            calendarTitle: event.calendar.title,
            calendarIdentifier: event.calendar.calendarIdentifier,
            attendees: attendees,
            organizerName: organizer.map { Self.participantName($0) },
            isEditable: event.calendar.allowsContentModifications && isOwn,
            eventIdentifier: event.eventIdentifier ?? ""
        )
    }

    private static func attendee(from participant: EKParticipant, organizer: EKParticipant?) -> CalendarEvent.Attendee {
        let status: CalendarEvent.Attendee.Status = switch participant.participantStatus {
        case .accepted, .completed, .inProcess: .accepted
        case .declined: .declined
        case .tentative, .delegated: .tentative
        case .pending: .pending
        case .unknown: .unknown
        @unknown default: .unknown
        }
        let email = Self.email(of: participant)
        let isOrganizer: Bool = if let organizer {
            organizer.url == participant.url
                || (email != nil && email == Self.email(of: organizer))
        } else {
            false
        }
        return CalendarEvent.Attendee(
            name: participant.name ?? "",
            email: email,
            status: status,
            isOrganizer: isOrganizer,
            isCurrentUser: participant.isCurrentUser
        )
    }

    /// `mailto:someone@host` → `someone@host`; anything else is not an email.
    private static func email(of participant: EKParticipant) -> String? {
        let url = participant.url
        guard url.scheme?.lowercased() == "mailto" else { return nil }
        let address = url.absoluteString.dropFirst("mailto:".count)
        return address.isEmpty ? nil : String(address)
    }

    private static func participantName(_ participant: EKParticipant) -> String {
        if let name = participant.name, !name.isEmpty { return name }
        return email(of: participant) ?? ""
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return text
    }

    /// Zoom/Meet/Teams links live either in the event URL or somewhere in the
    /// notes — check both so the user can join with one click.
    private static func meetingURL(for event: EKEvent) -> URL? {
        if let url = event.url, url.scheme?.hasPrefix("http") == true { return url }
        guard let notes = event.notes,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let range = NSRange(notes.startIndex..., in: notes)
        return detector.firstMatch(in: notes, range: range)?.url
    }
}

enum CalendarError: LocalizedError {
    case eventNotFound
    case noWritableCalendar

    var errorDescription: String? {
        switch self {
        case .eventNotFound: "The event no longer exists."
        case .noWritableCalendar: "No calendar accepts new events."
        }
    }
}
