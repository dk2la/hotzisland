import SwiftUI

/// Calendar: today's agenda fills in, the next meeting counts down and its
/// Join lights up, then "+" drops a new event into the evening.
struct CalendarStage: View {
    @State private var shown = 0
    @State private var minutes = 12
    @State private var joinFlash = false
    @State private var adding = false
    @State private var added = false

    private struct MockEvent {
        let title: L10nKey
        let start: String
        let end: String
        let color: Color
    }

    private static let events: [MockEvent] = [
        MockEvent(title: .obMockEvent1, start: "10:00", end: "10:15", color: StagePalette.blue),
        MockEvent(title: .obMockEvent2, start: "13:30", end: "14:30", color: StagePalette.orange),
        MockEvent(title: .obMockEvent3, start: "16:00", end: "16:30", color: StagePalette.purple),
    ]

    private static let newEvent = MockEvent(title: .obMockEvent4, start: "19:00", end: "20:00", color: StagePalette.teal)

    var body: some View {
        StagePanel(title: NotchTab.calendar.title) {
            StageGlyph("plus", active: adding)
            StageGlyph(CalendarDisplayMode.gridAndList.icon)
            StageGlyph(CalendarDisplayMode.listOnly.icon, active: true)
            StageGlyph("line.3.horizontal.decrease")
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                WeekStrip()
                HStack(spacing: 8) {
                    InstrumentLabel(L10n.t(.calToday), color: Theme.accent)
                    Hairline()
                }
                .padding(.top, 14)
                .padding(.bottom, 8)
                VStack(spacing: 6) {
                    ForEach(Self.events.indices, id: \.self) { index in
                        row(Self.events[index], isNext: index == 0)
                            .opacity(index < shown ? 1 : 0)
                            .offset(y: index < shown ? 0 : 10)
                            .animation(Theme.stateSpring, value: shown)
                    }
                    if added {
                        row(Self.newEvent, isNext: false)
                            .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
                    }
                }
            }
        }
        .storyboard(finalFrame: {
            shown = Self.events.count
            added = true
        }, loop: play)
    }

    private func row(_ event: MockEvent, isNext: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(event.color)
                .frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(event.title))
                    .font(Theme.bodyFont)
                    .fontWeight(isNext ? .semibold : .medium)
                    .lineLimit(1)
                    .foregroundStyle(isNext ? Theme.textPrimary : Theme.textSecondary)
                Text(isNext
                     ? "\(event.start) · \(L10n.f(.calStartsInMinutes, minutes))"
                     : "\(event.start) – \(event.end)")
                    .font(Theme.subFont)
                    .lineLimit(1)
                    .foregroundStyle(isNext ? Theme.accent : Theme.textTertiary)
            }
            Spacer(minLength: 0)
            if isNext {
                joinLabel
            }
        }
        .cardRow(raised: isNext)
    }

    /// EventRow's Join, flashing solid the moment it is "clicked".
    private var joinLabel: some View {
        InstrumentLabel(L10n.t(.calJoin), color: joinFlash ? Theme.inkOnAccent : Theme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(joinFlash ? Theme.accent : .clear))
            .overlay(Capsule().stroke(Theme.accentBorder, lineWidth: 1))
            .scaleEffect(joinFlash ? 0.92 : 1)
            .animation(.easeOut(duration: joinFlash ? 0.06 : 0.3), value: joinFlash)
    }

    private func play() async -> Bool {
        minutes = 12
        guard await beat(0.4) else { return false }
        for index in 1...Self.events.count {
            shown = index
            guard await beat(0.12) else { return false }
        }
        // Readouts jump, like the real countdown.
        for _ in 0..<2 {
            guard await beat(1.1) else { return false }
            minutes -= 1
        }
        guard await beat(0.7) else { return false }
        joinFlash = true
        guard await beat(0.18) else { return false }
        joinFlash = false
        guard await beat(1.0) else { return false }
        adding = true
        guard await beat(0.35) else { return false }
        withAnimation(Theme.stateSpring) { added = true }
        guard await beat(0.3) else { return false }
        adding = false
        guard await beat(2.8) else { return false }
        withAnimation(.easeIn(duration: 0.3)) {
            shown = 0
            added = false
        }
        return await beat(0.6)
    }
}

/// This week, Monday first, today in the accent disc — the month grid's
/// day cells laid out as a single row.
private struct WeekStrip: View {
    private let days: [Date]
    private let calendar: Calendar

    init() {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        self.calendar = calendar
        let today = calendar.startOfDay(for: Date())
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let isToday = calendar.isDateInToday(day)
                VStack(spacing: 5) {
                    Text(Self.weekday.string(from: day).uppercased())
                        .font(Theme.labelFont)
                        .foregroundStyle(isToday ? Theme.accent : Theme.textQuaternary)
                    ZStack {
                        if isToday {
                            Circle().fill(Theme.accent)
                        }
                        Text("\(calendar.component(.day, from: day))")
                            .font(Theme.dayFont)
                            .foregroundStyle(isToday ? Theme.islandFill : Theme.textSecondary)
                    }
                    .frame(width: 22, height: 22)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private static let weekday = DateFormatter(template: "EEEEE")
}
