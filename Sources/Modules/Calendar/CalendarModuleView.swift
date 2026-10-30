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
                action: ("Open Settings", {
                    PermissionGuide.shared.show(.calendars) {
                        Task { await service.requestAccess() }
                    }
                })
            )
        case .unknown:
            message(
                icon: "calendar",
                text: "No calendar access yet",
                action: ("Allow Access", { Task { await service.requestAccess() } })
            )
        }
    }

    /// The agenda: the week strip with one day, or the rolling list.
    @ViewBuilder
    private var browser: some View {
        switch service.displayMode {
        case .week:
            WeekView(service: service)
        case .listOnly:
            AgendaListView(service: service)
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
                ModuleButton(label: action.title, kind: .light, action: action.run)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
