import AppKit
import SwiftUI

/// "Calendar" tab. Agenda-first: list mode is the coming week with the next
/// meeting on top; the month grid stays one toggle away. Mode switching, the
/// visibility picker and back navigation live in the shared panel header.
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
            if service.showingPicker {
                CalendarPickerView(service: service)
            } else {
                switch service.displayMode {
                case .gridAndList:
                    VStack(spacing: 8) {
                        monthNav
                        // Side by side needs ~470pt (210pt grid + a usable
                        // list); narrower panels fold the grid away instead
                        // of crushing both halves.
                        GeometryReader { proxy in
                            if proxy.size.width < 470 {
                                EventListView(service: service, day: service.selectedDay)
                            } else {
                                HStack(alignment: .top, spacing: 14) {
                                    EventListView(service: service, day: service.selectedDay)
                                        .frame(maxWidth: .infinity)
                                    MonthGridView(service: service)
                                        .frame(width: 210)
                                }
                            }
                        }
                    }
                case .listOnly:
                    AgendaListView(service: service)
                case .gridOnly:
                    VStack(spacing: 8) {
                        monthNav
                        MonthGridView(service: service)
                            .frame(maxWidth: 260)
                        Spacer(minLength: 0)
                    }
                }
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
