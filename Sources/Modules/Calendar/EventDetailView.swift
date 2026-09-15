import AppKit
import SwiftUI

/// Calendar.app-style card for one event: colour bar and title, when,
/// which calendar, where, the meeting link, who is invited, and the notes.
/// Edit and Delete only show for events the user owns; invitees are
/// managed in Calendar.app, which "Open in Calendar" jumps to.
struct EventDetailView: View {
    var service: CalendarService
    let event: CalendarEvent

    /// Delete asks twice: the first click arms the button for 3 s.
    @State private var confirmingDelete = false
    @State private var confirmTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    block { header }
                    if event.location != nil || event.joinURL != nil {
                        block { details }
                    }
                    if !event.attendees.isEmpty {
                        block { attendees }
                    }
                    if let notes = event.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        block {
                            // Web, mail and phone references stay tappable.
                            Text(Self.linkified(notes))
                                .font(Theme.bodyFont)
                                .foregroundStyle(Theme.textSecondary)
                                .tint(Theme.accent)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.trailing, 2)
            }
            if let error = service.lastError {
                Text(error)
                    .font(Theme.subFont)
                    .lineLimit(2)
                    .foregroundStyle(Theme.critical)
            }
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDisappear { confirmTask?.cancel() }
    }

    // MARK: - Sections

    /// One block per group — the same card the mail reader uses, so the
    /// two modules read alike.
    private func block<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(event.color)
                    .frame(width: 4, height: 18)
                    .padding(.top, 1)
                Text(event.title)
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
            }
            Text(whenLine)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textQuaternary)
                .padding(.leading, 14)
            Text(event.calendarTitle)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 14)
        }
    }

    @ViewBuilder
    private var details: some View {
        if let location = event.location {
            Button {
                openInMaps(location)
            } label: {
                detailRow(icon: "mappin") {
                    Text(location)
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
        if let link = event.joinURL {
            detailRow(icon: "video") {
                Text(link.host ?? link.absoluteString)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                GlassCapsuleButton(label: L10n.t(.calJoin), isPrimary: true) {
                    NSWorkspace.shared.open(link)
                }
            }
        }
    }

    private var attendees: some View {
        VStack(alignment: .leading, spacing: 6) {
            InstrumentLabel("\(L10n.t(.calAttendees)) (\(event.attendees.count))")
            ForEach(Array(event.attendees.enumerated()), id: \.offset) { _, attendee in
                attendeeRow(attendee)
            }
        }
    }

    private func attendeeRow(_ attendee: CalendarEvent.Attendee) -> some View {
        HStack(spacing: 8) {
            let key = attendee.email ?? attendee.name
            Text(SenderAvatarView.initials(name: attendee.name, address: attendee.email ?? ""))
                .font(.system(size: 22 * 0.34, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 22, height: 22)
                .background(SenderAvatarView.color(for: key), in: Circle())
            Text(attendee.displayName)
                .font(Theme.bodyFont)
                .foregroundStyle(attendee.isCurrentUser ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if attendee.isOrganizer {
                InstrumentLabel(L10n.t(.calOrganizer), color: Theme.textQuaternary)
            }
            Spacer(minLength: 0)
            Image(systemName: statusGlyph(attendee.status).name)
                .font(Theme.iconSmallFont)
                .foregroundStyle(statusGlyph(attendee.status).color)
        }
    }

    private func statusGlyph(_ status: CalendarEvent.Attendee.Status) -> (name: String, color: Color) {
        switch status {
        case .accepted: ("checkmark.circle", Theme.accent)
        case .declined: ("xmark.circle", Theme.critical)
        case .tentative: ("questionmark.circle", Theme.textTertiary)
        case .pending, .unknown: ("circle", Theme.textQuaternary)
        }
    }

    /// Web, mail and phone references in the notes become tappable links;
    /// plain text stays plain. Calendar invites are full of these.
    private static func linkified(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
                | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
        ) else { return result }
        let nsText = text as NSString
        for match in detector.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let url: URL? = switch match.resultType {
            case .link: match.url
            case .phoneNumber: match.phoneNumber.flatMap { number in
                URL(string: "tel:" + number.filter { $0.isNumber || $0 == "+" })
            }
            default: nil
            }
            guard let url,
                  let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result)
            else { continue }
            result[lower..<upper].link = url
            result[lower..<upper].underlineStyle = .single
        }
        return result
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if event.isEditable {
                GlassCapsuleButton(label: L10n.t(.calEdit), systemName: "pencil") {
                    service.startEditing(event)
                }
            }
            GlassCapsuleButton(label: L10n.t(.calOpenInCalendar), systemName: "arrow.up.forward.app") {
                service.openInCalendarApp(event)
            }
            Spacer(minLength: 0)
            if event.isEditable {
                GlassCapsuleButton(
                    label: confirmingDelete ? L10n.t(.calConfirmDelete) : L10n.t(.calDelete),
                    systemName: "trash",
                    tint: Theme.critical
                ) {
                    deleteTapped()
                }
            }
        }
        .animation(Theme.stateSpring, value: confirmingDelete)
    }

    // MARK: - Helpers

    private func detailRow<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(Theme.iconSmallFont)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 14)
            content()
        }
    }

    /// "Tue 15 Sep · 15:00 – 15:30"; a multi-day event names both ends.
    private var whenLine: String {
        let calendar = service.calendar
        let day = Self.dayFormatter.string(from: event.start)
        if event.isAllDay {
            let lastDay = calendar.startOfDay(for: max(event.start, event.end - 1))
            if calendar.isDate(lastDay, inSameDayAs: event.start) {
                return "\(day) · \(L10n.t(.calAllDay))"
            }
            return "\(day) – \(Self.dayFormatter.string(from: lastDay)) · \(L10n.t(.calAllDay))"
        }
        let start = Self.timeFormatter.string(from: event.start)
        let end = Self.timeFormatter.string(from: event.end)
        if calendar.isDate(event.start, inSameDayAs: event.end) {
            return "\(day) · \(start) – \(end)"
        }
        return "\(day) \(start) – \(Self.dayFormatter.string(from: event.end)) \(end)"
    }

    private func openInMaps(_ location: String) {
        let query = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? location
        guard let url = URL(string: "maps://?q=\(query)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func deleteTapped() {
        guard confirmingDelete else {
            confirmingDelete = true
            confirmTask?.cancel()
            confirmTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                confirmingDelete = false
            }
            return
        }
        confirmTask?.cancel()
        confirmingDelete = false
        do {
            try service.delete(event)
        } catch {
            service.lastError = error.localizedDescription
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter
    }()
}
