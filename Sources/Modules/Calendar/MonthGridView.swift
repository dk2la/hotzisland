import SwiftUI

/// Month grid: six fixed rows so the layout never jumps between months.
struct MonthGridView: View {
    var service: CalendarService

    private var calendar: Calendar { service.calendar }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        // Rotate so the week starts on the calendar's first weekday.
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var days: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: service.displayedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else { return [] }
        return (0..<42).compactMap {
            calendar.date(byAdding: .day, value: $0, to: firstWeek.start)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let index = row * 7 + column
                        if index < days.count {
                            dayCell(days[index])
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = calendar.isDate(day, inSameDayAs: service.selectedDay)
        let inMonth = calendar.isDate(day, equalTo: service.displayedMonth, toGranularity: .month)

        return Button {
            service.select(day: day)
        } label: {
            ZStack {
                if isToday {
                    Circle().fill(Theme.accentToday)
                } else if isSelected {
                    Circle().stroke(Theme.textTertiary, lineWidth: 1)
                }
                Text("\(calendar.component(.day, from: day))")
                    .font(Theme.dayFont)
                    .foregroundStyle(dayColor(isToday: isToday, inMonth: inMonth))
            }
            .frame(width: 22, height: 22)
            .overlay(alignment: .bottom) {
                if service.hasEvents(on: day), !isToday {
                    Circle()
                        .fill(Theme.textTertiary)
                        .frame(width: 3, height: 3)
                        .offset(y: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: 26)
    }

    private func dayColor(isToday: Bool, inMonth: Bool) -> Color {
        if isToday { return Theme.textPrimary }
        return inMonth ? Theme.textPrimary : Theme.textQuaternary
    }
}
