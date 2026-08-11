import AppKit
import SwiftUI

/// "Calendar" tab: month grid and/or the selected day's events, plus a
/// calendar-visibility picker.
struct CalendarModuleView: View {
    var service: CalendarService
    @State private var showingPicker = false

    var body: some View {
        VStack(spacing: 8) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if service.access == .granted, !showingPicker {
                navigation
            } else {
                Text(showingPicker ? "Calendars" : "Calendar")
                    .font(Theme.headlineFont)
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer(minLength: 0)
            if service.access == .granted {
                if !showingPicker {
                    modeSwitcher
                }
                iconButton(showingPicker ? "xmark" : "line.3.horizontal.decrease") {
                    showingPicker.toggle()
                }
            }
        }
    }

    /// Month arrows in grid modes, day arrows in list-only mode.
    private var navigation: some View {
        HStack(spacing: 6) {
            iconButton("chevron.left") {
                service.displayMode.showsGrid ? service.step(months: -1) : service.step(days: -1)
            }
            Button {
                service.goToToday()
            } label: {
                Text(titleText)
                    .font(Theme.headlineFont)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 116)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            iconButton("chevron.right") {
                service.displayMode.showsGrid ? service.step(months: 1) : service.step(days: 1)
            }
        }
    }

    private var titleText: String {
        if service.displayMode == .listOnly {
            return service.calendar.isDateInToday(service.selectedDay)
                ? "Today"
                : Self.dayFormatter.string(from: service.selectedDay)
        }
        return Self.monthFormatter.string(from: service.displayedMonth)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(CalendarDisplayMode.allCases) { mode in
                let isActive = service.displayMode == mode
                Button {
                    service.setDisplayMode(mode)
                } label: {
                    Image(systemName: mode.icon)
                        .font(Theme.iconSmallFont)
                        .foregroundStyle(isActive ? Theme.amber : Theme.textQuaternary)
                        .frame(width: 22, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch service.access {
        case .granted:
            if showingPicker {
                CalendarPickerView(service: service)
            } else {
                switch service.displayMode {
                case .gridAndList:
                    HStack(alignment: .top, spacing: 14) {
                        EventListView(service: service, day: service.selectedDay)
                            .frame(maxWidth: .infinity)
                        MonthGridView(service: service)
                            .frame(width: 210)
                    }
                case .listOnly:
                    EventListView(service: service, day: service.selectedDay)
                case .gridOnly:
                    MonthGridView(service: service)
                        .frame(maxWidth: 260)
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
                    InstrumentLabel(action.title, color: Theme.amber)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.controlRadius)
                                .stroke(Theme.amberBorder, lineWidth: 1)
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

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
    }()
}
