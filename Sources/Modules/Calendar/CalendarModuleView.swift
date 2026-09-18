import AppKit
import SwiftUI

/// "Calendar" tab. Agenda-first: list mode is the coming week with the next
/// meeting on top; the month grid stays one toggle away. Clicking an event
/// opens its detail card in place; "+" and Edit open the event form. Mode
/// switching, the visibility picker and back navigation live in the shared
/// panel header.
struct CalendarModuleView: View {
    var service: CalendarService

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch service.access {
        case .granted:
            if service.isCreating || service.editingEvent != nil {
                // Distinct identity per form so a fresh draft is built when
                // switching between creating and editing.
                EventEditorView(service: service, editing: service.editingEvent)
                    .id(service.editingEvent?.id ?? "new")
            } else if let event = service.selectedEvent {
                EventDetailView(service: service, event: event)
                    .transition(.opacity)
            } else if service.showingPicker {
                CalendarPickerView(service: service)
            } else {
                browser
            }
        case .denied:
            message(
                icon: "lock.fill",
                text: "Calendar access denied",
                action: ("Open Settings", openPrivacySettings)
            )
        case .unknown:
            message(icon: "calendar", text: "Requesting access…", action: nil)
        }
    }

    /// The agenda: grid, list or both, per display mode.
    @ViewBuilder
    private var browser: some View {
                switch service.displayMode {
                case .gridAndList:
                    GeometryReader { proxy in
                        // The grid keeps its natural row height while a third
                        // of the panel allows it, then shrinks its rows. The
                        // whole column scrolls as one, so on a small panel
                        // the grid simply scrolls away above the events.
                        let gridBudget = proxy.size.height / 3
                        let rowHeight = min(26, max(18, (gridBudget - 16 - 16 - 4 - 20) / 6))
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 8) {
                                monthNav
                                MonthGridView(service: service, rowHeight: rowHeight)
                                    .padding(.horizontal, 8)
                                    .padding(.top, 10)
                                    .padding(.bottom, 6)
                                    .frame(maxWidth: .infinity)
                                    .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                                HStack(spacing: 8) {
                                    InstrumentLabel(dayLabel(service.selectedDay), color: Theme.accent)
                                    Hairline()
                                }
                                .padding(.top, 4)
                                EventListView(service: service, day: service.selectedDay, embedded: true)
                                    .frame(maxWidth: .infinity, alignment: .top)
                            }
                        }
                    }
                case .listOnly:
                    AgendaListView(service: service)
                }
    }

    private func dayLabel(_ day: Date) -> String {
        if service.calendar.isDateInToday(day) { return L10n.t(.calToday) }
        if service.calendar.isDateInTomorrow(day) { return L10n.t(.calTomorrow) }
        return Self.dayFormatter.string(from: day)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
    }()

    /// Month furniture — arrows and the tappable "back to today" title. It
    /// belongs to the grid, so it only appears with one.
    private var monthNav: some View {
        HStack(spacing: 6) {
            iconButton("chevron.left") { service.step(months: -1) }
            Button {
                service.goToToday()
            } label: {
                Text(Self.monthFormatter.string(from: service.displayedMonth))
                    .font(Theme.headlineFont)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 116)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            iconButton("chevron.right") { service.step(months: 1) }
            Spacer(minLength: 0)
        }
    }

    private func message(
        icon: String,
        text: String,
        action: (title: String, run: () -> Void)?
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(Theme.iconLargeFont)
                .foregroundStyle(Theme.textQuaternary)
            Text(text)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textQuaternary)
            if let action {
                Button(action: action.run) {
                    InstrumentLabel(action.title, color: Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.controlRadius)
                                .stroke(Theme.accentBorder, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.iconSmallFont)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()
}
