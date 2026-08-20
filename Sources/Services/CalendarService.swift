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
    private(set) var displayMode: CalendarDisplayMode = .gridAndList

    var displayedMonth: Date = Date()
    var selectedDay: Date = Calendar.current.startOfDay(for: Date())

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
            access = granted ? .granted : .denied
        } catch {
            access = .denied
        }
        log.info("calendar access: \(String(describing: self.access), privacy: .public)")
        if access == .granted { reload() }
    }

    // MARK: - Settings

    func setDisplayMode(_ mode: CalendarDisplayMode) {
        displayMode = mode
        defaults.set(mode.rawValue, forKey: Self.modeKey)
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
        defaults.set(Array(enabledCalendarIDs), forKey: Self.enabledKey)
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

    // MARK: - Loading

    func reload() {
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

        let active = ekCalendars.filter { isEnabled($0.calendarIdentifier) }
        guard !active.isEmpty,
              let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              // Pad by a week on both sides so leading/trailing grid days
              // also show their event dots.
              let start = calendar.date(byAdding: .day, value: -7, to: monthInterval.start),
              let end = calendar.date(byAdding: .day, value: 7, to: monthInterval.end)
        else {
            eventsByDay = [:]
            return
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: active)
        var grouped: [Date: [CalendarEvent]] = [:]
        // The same meeting often exists in several calendars (work Exchange +
        // Google invite) — deduplicate by title and exact time.
        var seen = Set<String>()
        for event in store.events(matching: predicate) {
            guard let start = event.startDate else { continue }
            let dedupKey = "\(event.title ?? "")|\(start.timeIntervalSince1970)|\(event.endDate?.timeIntervalSince1970 ?? 0)"
            guard seen.insert(dedupKey).inserted else { continue }
            let day = calendar.startOfDay(for: start)
            grouped[day, default: []].append(
                CalendarEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "(No title)",
                    start: start,
                    end: event.endDate ?? start,
                    isAllDay: event.isAllDay,
                    color: Color(nsColor: event.calendar.color ?? .systemBlue),
                    joinURL: Self.meetingURL(for: event)
                )
            )
        }
        for (day, events) in grouped {
            grouped[day] = events.sorted { lhs, rhs in
                lhs.isAllDay == rhs.isAllDay ? lhs.start < rhs.start : lhs.isAllDay
            }
        }
        eventsByDay = grouped
        log.info("""
        loaded calendars=\(self.calendars.count, privacy: .public) \
        sources=\(Set(self.calendars.map(\.sourceTitle)).sorted().joined(separator: ","), privacy: .public) \
        active=\(active.count, privacy: .public) \
        days=\(grouped.count, privacy: .public) \
        events=\(grouped.values.map(\.count).reduce(0, +), privacy: .public)
        """)
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
