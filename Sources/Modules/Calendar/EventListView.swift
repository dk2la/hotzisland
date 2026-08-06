import AppKit
import SwiftUI

/// Events of the selected day: time, title and a click-through to the
/// meeting link when the event has one.
struct EventListView: View {
    var service: CalendarService
    let day: Date

    private var events: [CalendarEvent] { service.events(forDay: day) }

    var body: some View {
        if events.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(Theme.iconFont)
                    .foregroundStyle(Theme.textQuaternary)
                Text("No events")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textQuaternary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(events) { event in
                        row(for: event)
                    }
                }
            }
        }
    }

    private func row(for event: CalendarEvent) -> some View {
        Button {
            if let url = event.joinURL {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 7) {
                Capsule()
                    .fill(event.color)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(Theme.bodyFont)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textPrimary)
                    Text(timeLabel(for: event))
                        .font(Theme.captionFont.monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
                if event.joinURL != nil {
                    Image(systemName: "video.fill")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func timeLabel(for event: CalendarEvent) -> String {
        guard !event.isAllDay else { return "All day" }
        return "\(Self.formatter.string(from: event.start)) – \(Self.formatter.string(from: event.end))"
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
