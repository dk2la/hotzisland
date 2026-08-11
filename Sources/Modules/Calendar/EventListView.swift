import AppKit
import SwiftUI

/// Events of the selected day as data registers: mono time column, title,
/// mono annotation. The next joinable event gets an amber countdown.
struct EventListView: View {
    var service: CalendarService
    let day: Date

    private var events: [CalendarEvent] { service.events(forDay: day) }

    /// The first upcoming event today — its annotation counts down in amber.
    private var nextEvent: CalendarEvent? {
        guard service.calendar.isDateInToday(day) else { return nil }
        return events.first { !$0.isAllDay && $0.end > Date() }
    }

    var body: some View {
        if events.isEmpty {
            DashedZone(label: "no events")
                .frame(maxHeight: 90)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        row(for: event)
                        if event.id != events.last?.id {
                            Hairline()
                        }
                    }
                }
            }
        }
    }

    private func row(for event: CalendarEvent) -> some View {
        let isNext = event.id == nextEvent?.id
        return Button {
            if let url = event.joinURL {
                NSWorkspace.shared.open(url)
            }
        } label: {
            DataRow(
                leading: event.isAllDay ? "—" : Self.timeFormatter.string(from: event.start),
                title: event.title,
                titleColor: isNext ? Theme.textPrimary : Theme.textPrimary.opacity(0.8)
            ) {
                Text(annotation(for: event, isNext: isNext))
                    .font(Theme.readoutSFont)
                    .foregroundStyle(isNext ? Theme.amber : Theme.textPrimary.opacity(0.35))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func annotation(for event: CalendarEvent, isNext: Bool) -> String {
        if isNext {
            let minutes = max(0, Int(event.start.timeIntervalSinceNow / 60))
            let countdown = event.start > Date() ? "T−\(minutes)m" : "now"
            return event.joinURL != nil ? "\(countdown) · join" : countdown
        }
        if event.isAllDay { return "all day" }
        let minutes = Int(event.end.timeIntervalSince(event.start) / 60)
        return minutes >= 60 ? String(format: "%dh%02d", minutes / 60, minutes % 60) : "\(minutes)m"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
