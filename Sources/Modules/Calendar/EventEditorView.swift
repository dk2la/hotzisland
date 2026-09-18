import SwiftUI

/// Create/edit form on an opaque sheet filling the module: title, calendar,
/// all-day, start/end, location, URL, notes, then Cancel / Save. Invitees
/// cannot be set through EventKit on macOS — the caption under the fields
/// sends the user to Calendar.app for that.
struct EventEditorView: View {
    var service: CalendarService
    /// nil while creating; the event being rewritten otherwise.
    var editing: CalendarEvent?

    @State private var draft: EventDraft
    @FocusState private var titleFocused: Bool

    init(service: CalendarService, editing: CalendarEvent?) {
        self.service = service
        self.editing = editing
        let initial = editing.map { EventDraft(event: $0, calendar: service.calendar) } ?? service.newDraft()
        _draft = State(initialValue: initial)
    }

    private var isNew: Bool { editing == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t(isNew ? .calNewEvent : .calEditEvent))
                .font(Theme.headlineFont)
                .foregroundStyle(Theme.textPrimary)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    fields
                    inviteesHint
                }
                .padding(.trailing, 4)
            }
            if let error = service.lastError {
                Text(error)
                    .font(Theme.subFont)
                    .lineLimit(2)
                    .foregroundStyle(Theme.critical)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                GlassCapsuleButton(label: L10n.t(.mailCancel)) {
                    cancel()
                }
                GlassCapsuleButton(label: L10n.t(.calSave), isPrimary: true, enabled: draft.isValid) {
                    save()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Opaque on purpose: nothing may show through under text being
        // typed — same rule as the mail reply sheet.
        .background(Theme.sheetFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .onAppear { titleFocused = true }
        .onChange(of: draft.isAllDay) { _, allDay in
            if allDay {
                draft.start = service.calendar.startOfDay(for: draft.start)
                draft.end = service.calendar.startOfDay(for: max(draft.start, draft.end))
            } else if draft.end <= draft.start {
                draft.end = draft.start.addingTimeInterval(3600)
            }
        }
        .onChange(of: draft.start) { old, new in
            // Moving the start drags the end along, keeping the duration
            // (whole days for an all-day event).
            let calendar = service.calendar
            if draft.isAllDay {
                let days = calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: old),
                    to: calendar.startOfDay(for: draft.end)
                ).day ?? 0
                draft.end = calendar.date(byAdding: .day, value: max(0, days), to: new) ?? new
            } else {
                let duration = max(0, draft.end.timeIntervalSince(old))
                draft.end = new.addingTimeInterval(duration)
            }
        }
    }

    // MARK: - Fields

    private var fields: some View {
        VStack(spacing: 0) {
            fieldRow(L10n.t(.calTitleField)) {
                TextField("", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textPrimary)
                    .focused($titleFocused)
            }
            Hairline()
            fieldRow(L10n.t(.calCalendarField)) {
                calendarPicker
                Spacer(minLength: 0)
            }
            Hairline()
            fieldRow(L10n.t(.calAllDay)) {
                InstrumentToggle(isOn: $draft.isAllDay, palette: .rack)
                Spacer(minLength: 0)
            }
            Hairline()
            fieldRow(L10n.t(.calStarts)) {
                datePicker($draft.start)
                Spacer(minLength: 0)
            }
            Hairline()
            fieldRow(L10n.t(.calEnds)) {
                datePicker($draft.end)
                Spacer(minLength: 0)
            }
            Hairline()
            fieldRow(L10n.t(.calLocationField)) {
                TextField("", text: $draft.location)
                    .textFieldStyle(.plain)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textPrimary)
            }
            Hairline()
            fieldRow(L10n.t(.calURLField)) {
                TextField("", text: $draft.url)
                    .textFieldStyle(.plain)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textPrimary)
            }
            Hairline()
            fieldRow(L10n.t(.calNotesField), alignment: .top) {
                TextEditor(text: $draft.notes)
                    .scrollContentBackground(.hidden)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minHeight: 54)
                    .padding(.leading, -5)
            }
        }
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func fieldRow<Content: View>(
        _ label: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: 8) {
            Text(label)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textQuaternary)
                .frame(width: 62, alignment: .leading)
                .padding(.top, alignment == .top ? 3 : 0)
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var calendarPicker: some View {
        let current = service.writableCalendars.first { $0.id == draft.calendarIdentifier }
        return Menu {
            ForEach(service.writableCalendars) { calendar in
                Button {
                    draft.calendarIdentifier = calendar.id
                } label: {
                    if calendar.id == draft.calendarIdentifier {
                        Label(calendar.title, systemImage: "checkmark")
                    } else {
                        Text(calendar.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(current?.color ?? Theme.textQuaternary)
                    .frame(width: 8, height: 8)
                Text(current?.title ?? "—")
                    .font(Theme.subFont)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.raisedFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func datePicker(_ date: Binding<Date>) -> some View {
        DatePicker(
            "",
            selection: date,
            displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute]
        )
        .datePickerStyle(.field)
        .labelsHidden()
        // AppKit-backed control: pin it to the dark appearance so it does
        // not draw black text on the dark sheet under a light system theme.
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }

    /// EventKit cannot add attendees on macOS; Calendar.app can. For an
    /// existing event the link saves the form first, then hands over.
    private var inviteesHint: some View {
        HStack(spacing: 6) {
            Text(L10n.t(.calInviteesHint))
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textQuaternary)
            if let editing {
                Button {
                    save()
                    // `save` replaces the selection with the fresh snapshot;
                    // fall back to the original if it failed.
                    service.openInCalendarApp(service.selectedEvent ?? editing)
                } label: {
                    Text(L10n.t(.calOpenInCalendar))
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    // MARK: - Actions

    private func save() {
        do {
            try service.save(draft: draft)
        } catch {
            service.lastError = error.localizedDescription
        }
    }

    private func cancel() {
        if isNew {
            service.cancelCreating()
        } else {
            service.cancelEditing()
        }
    }
}
