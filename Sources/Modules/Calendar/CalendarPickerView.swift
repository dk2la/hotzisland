import SwiftUI

/// Calendar visibility picker — every account configured in the system
/// (iCloud, Google, Exchange, …) grouped by source.
struct CalendarPickerView: View {
    var service: CalendarService

    private var grouped: [(source: String, calendars: [CalendarInfo])] {
        Dictionary(grouping: service.calendars, by: \.sourceTitle)
            .map { (source: $0.key, calendars: $0.value) }
            .sorted { $0.source < $1.source }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(grouped, id: \.source) { group in
                    Text(group.source)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textTertiary)
                    ForEach(group.calendars) { calendar in
                        row(for: calendar)
                    }
                }
            }
            .padding(.trailing, 4)
        }
    }

    private func row(for calendar: CalendarInfo) -> some View {
        Button {
            service.toggleCalendar(calendar.id)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: service.isEnabled(calendar.id) ? "checkmark.circle.fill" : "circle")
                    .font(Theme.iconSmallFont)
                    .foregroundStyle(service.isEnabled(calendar.id) ? calendar.color : Theme.textQuaternary)
                Text(calendar.title)
                    .font(Theme.bodyFont)
                    .lineLimit(1)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
