import Foundation
import OSLog

/// What one tool run produced. Typed, because sniffing an "Error:" prefix
/// would break the moment a tool result legitimately starts with that word.
struct ToolOutcome {
    var text: String
    var isError = false
    /// Set by `run_playbook`: the playbook waits for the user's confirmation
    /// instead of running — a playbook can close every open app.
    var playbookToConfirm: Playbook?

    static func failure(_ text: String) -> ToolOutcome {
        ToolOutcome(text: text, isError: true)
    }
}

/// The assistant's hands: a fixed registry of tools executed on the main
/// actor against the live module services. One `specs` table feeds both wire
/// formats — the OpenAI function schema and the CLI prose list — so a new
/// tool cannot ship in one and silently miss the other.
@MainActor
final class AssistantToolbox {
    // The toolbox is owned by AssistantService inside ModuleServices, so a
    // strong back-reference would cycle.
    private unowned let services: ModuleServices
    private unowned let playbooks: PlaybookStore
    private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "assistant")

    init(services: ModuleServices, playbooks: PlaybookStore) {
        self.services = services
        self.playbooks = playbooks
    }

    // MARK: - Registry

    private struct ToolSpec {
        var name: String
        var description: String
        /// Example arguments shown to CLI-backed models, e.g. `{"minutes": 25}`.
        var exampleArguments: String
        var parameters: [String: [String: String]] = [:]
        var required: [String] = []
    }

    private static let specs: [ToolSpec] = [
        ToolSpec(
            name: "set_timer",
            description: "Start a countdown timer in the widget.",
            exampleArguments: #"{"minutes": 25}"#,
            parameters: ["minutes": ["type": "number", "description": "Duration in minutes (1-240)"]],
            required: ["minutes"]
        ),
        ToolSpec(
            name: "run_playbook",
            description: "Run one of the user's playbooks (opens/closes apps, runs a shortcut) by name.",
            exampleArguments: #"{"name": "Focus"}"#,
            parameters: ["name": ["type": "string", "description": "Playbook name, exact or approximate"]],
            required: ["name"]
        ),
        ToolSpec(
            name: "timer_control",
            description: "Pause, resume or stop the running timer.",
            exampleArguments: #"{"action": "stop"}"#,
            parameters: ["action": ["type": "string", "description": "One of: pause, resume, stop"]],
            required: ["action"]
        ),
        ToolSpec(name: "now_playing", description: "What music is currently playing.", exampleArguments: "{}"),
        ToolSpec(
            name: "media_control",
            description: "Control music playback: play/pause toggle, next or previous track.",
            exampleArguments: #"{"action": "pause"}"#,
            parameters: ["action": ["type": "string", "description": "One of: play, pause, next, previous"]],
            required: ["action"]
        ),
        ToolSpec(name: "today_events", description: "The user's calendar events for today.", exampleArguments: "{}"),
        ToolSpec(
            name: "events_on",
            description: "The user's calendar events on a given date.",
            exampleArguments: #"{"date": "2026-09-18"}"#,
            parameters: ["date": ["type": "string", "description": "Date as YYYY-MM-DD, or 'tomorrow'"]],
            required: ["date"]
        ),
        ToolSpec(
            name: "create_event",
            description: "Create a calendar event. Asks the user to confirm before saving.",
            exampleArguments: #"{"title": "Dentist", "start": "2026-09-18T15:00", "minutes": 60}"#,
            parameters: [
                "title": ["type": "string", "description": "Event title"],
                "start": ["type": "string", "description": "Start as YYYY-MM-DDTHH:MM in the user's local time"],
                "minutes": ["type": "number", "description": "Duration in minutes (default 60)"],
            ],
            required: ["title", "start"]
        ),
        ToolSpec(
            name: "create_note",
            description: "Save a note to the user's notes folder.",
            exampleArguments: #"{"text": "buy milk"}"#,
            parameters: ["text": ["type": "string", "description": "Note text; the first line becomes the title"]],
            required: ["text"]
        ),
        ToolSpec(name: "unread_email_count", description: "How many unread emails the user has.", exampleArguments: "{}"),
        ToolSpec(name: "unread_emails", description: "The newest unread emails: sender, subject, time.", exampleArguments: "{}"),
        ToolSpec(
            name: "search_email",
            description: "Search the user's mail by sender or subject; also opens the search in the Mail module.",
            exampleArguments: #"{"query": "invoice"}"#,
            parameters: ["query": ["type": "string", "description": "Words to look for in sender or subject"]],
            required: ["query"]
        ),
        ToolSpec(
            name: "open_email",
            description: "Open an email in the widget by sender or subject.",
            exampleArguments: #"{"query": "Frank invitation"}"#,
            parameters: ["query": ["type": "string", "description": "Sender or subject words identifying the message"]],
            required: ["query"]
        ),
        ToolSpec(
            name: "open_note",
            description: "Open one of the user's notes by title.",
            exampleArguments: #"{"title": "Meeting notes"}"#,
            parameters: ["title": ["type": "string", "description": "Note title, exact or approximate"]],
            required: ["title"]
        ),
        ToolSpec(
            name: "append_note",
            description: "Append text to the note that is open in the widget (or save it as a new note if none is open).",
            exampleArguments: #"{"text": "- call the dentist"}"#,
            parameters: ["text": ["type": "string", "description": "Text to add at the end"]],
            required: ["text"]
        ),
        ToolSpec(name: "list_playbooks", description: "The user's playbooks and what each one does.", exampleArguments: "{}"),
    ]

    /// OpenAI function-calling declarations for the HTTP backend.
    static let declarations: [[String: Any & Sendable]] = specs.map { spec in
        let schema: [String: Any & Sendable] = [
            "type": "object",
            "properties": spec.parameters,
            "required": spec.required,
        ]
        let function: [String: Any & Sendable] = [
            "name": spec.name,
            "description": spec.description,
            "parameters": schema,
        ]
        return ["type": "function", "function": function]
    }

    /// Prose tool list for the CLI backends, which speak plain text and use
    /// the `CLIToolProtocol` marker instead of the tool-calling wire format.
    static let cliInstructions: String = {
        let lines = specs
            .map { "- \($0.name) \($0.exampleArguments) — \($0.description)" }
            .joined(separator: "\n")
        return """
            To act on the widget, reply with ONLY this one line and nothing else:
            \(CLIToolProtocol.marker)tool_name {"arg": "value"}>>
            Available tools:
            \(lines)
            You will then receive a TOOL RESULT line; after it, answer the user in \
            prose. Never claim a tool ran unless you saw its TOOL RESULT.
            """
    }()

    // MARK: - Execution

    /// A short human-readable rendering for the transcript, e.g. "set_timer(25)".
    static func label(name: String, argumentsJSON: String) -> String {
        let arguments = decode(argumentsJSON)
        let rendered = arguments
            .sorted { $0.key < $1.key }
            .map { _, value in shortValue(value) }
            .joined(separator: ", ")
        return "\(name)(\(rendered))"
    }

    func execute(name: String, argumentsJSON: String) -> ToolOutcome {
        let arguments = Self.decode(argumentsJSON)
        log.info("tool \(name, privacy: .public)")
        switch name {
        case "set_timer":
            guard let minutes = Self.number(arguments["minutes"]), minutes > 0 else {
                return .failure("'minutes' must be a positive number.")
            }
            let clamped = min(max(minutes, 1), 240)
            let timer = services.timerService
            // setDuration/start are no-ops on a running timer: stop it first,
            // and report only what actually happened.
            timer.reset()
            timer.setDuration(clamped * 60)
            timer.start()
            guard timer.isRunning else {
                return .failure("The timer could not be started.")
            }
            return ToolOutcome(text: "Timer started for \(Int(clamped)) minutes.")

        case "run_playbook":
            guard let query = (arguments["name"] as? String)?
                .trimmingCharacters(in: .whitespaces), !query.isEmpty else {
                return .failure("'name' is required.")
            }
            let all = playbooks.playbooks
            guard !all.isEmpty else { return ToolOutcome(text: "The user has no playbooks yet.") }
            let match = all.first { $0.name.caseInsensitiveCompare(query) == .orderedSame }
                ?? all.first { $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            guard let match else {
                let names = all.map(\.name).joined(separator: ", ")
                return ToolOutcome(text: "No playbook matches \"\(query)\". Available: \(names).")
            }
            // Never run silently: the service shows a Confirm/Cancel row and
            // calls `runPlaybook` only on the user's say-so.
            return ToolOutcome(
                text: "Asked the user to confirm running playbook \"\(match.name)\". Do not claim it ran.",
                playbookToConfirm: match
            )

        case "timer_control":
            let timer = services.timerService
            switch (arguments["action"] as? String ?? "").lowercased() {
            case "pause":
                guard timer.isRunning else { return ToolOutcome(text: "No timer is running.") }
                timer.pause()
                return ToolOutcome(text: "Timer paused with \(Int(timer.remaining / 60)) minutes left.")
            case "resume", "continue", "start":
                guard !timer.isRunning, timer.remaining > 0 else {
                    return ToolOutcome(text: timer.isRunning ? "The timer is already running." : "There is no paused timer to resume.")
                }
                timer.start()
                return ToolOutcome(text: "Timer resumed, \(Int(timer.remaining / 60)) minutes left.")
            case "stop", "cancel", "reset":
                guard timer.isRunning || timer.remaining != timer.duration else {
                    return ToolOutcome(text: "No timer is running.")
                }
                timer.reset()
                return ToolOutcome(text: "Timer stopped.")
            default:
                return .failure("'action' must be pause, resume or stop.")
            }

        case "media_control":
            let media = services.mediaCenter
            guard let track = media.track else { return ToolOutcome(text: "Nothing is playing.") }
            switch (arguments["action"] as? String ?? "").lowercased() {
            case "play":
                guard !track.isPlaying else { return ToolOutcome(text: "Already playing \(track.title).") }
                media.togglePlayPause()
                return ToolOutcome(text: "Resumed \(track.title).")
            case "pause", "stop":
                guard track.isPlaying else { return ToolOutcome(text: "Already paused.") }
                media.togglePlayPause()
                return ToolOutcome(text: "Paused \(track.title).")
            case "next", "skip":
                media.next()
                return ToolOutcome(text: "Skipped to the next track.")
            case "previous", "back":
                media.previous()
                return ToolOutcome(text: "Went back to the previous track.")
            default:
                return .failure("'action' must be play, pause, next or previous.")
            }

        case "events_on":
            guard let day = Self.parseDay(arguments["date"] as? String ?? "") else {
                return .failure("'date' must be YYYY-MM-DD, 'today' or 'tomorrow'.")
            }
            let events = services.calendarService.events(forDay: day)
            let dayName = Self.dayFormatter.string(from: day)
            guard !events.isEmpty else { return ToolOutcome(text: "No events on \(dayName).") }
            let lines = events.map { event in
                event.isAllDay
                    ? "all day — \(event.title)"
                    : "\(Self.eventTimeFormatter.string(from: event.start))–\(Self.eventTimeFormatter.string(from: event.end)) \(event.title)"
            }
            return ToolOutcome(text: "\(dayName):\n" + lines.joined(separator: "\n"))

        case "create_event":
            guard let title = (arguments["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return .failure("'title' is required.")
            }
            guard let start = Self.parseDateTime(arguments["start"] as? String ?? "") else {
                return .failure("'start' must be YYYY-MM-DDTHH:MM.")
            }
            let calendarService = services.calendarService
            guard calendarService.access == .granted else {
                return ToolOutcome(text: "Calendar access is not granted in the widget.")
            }
            guard let calendarID = calendarService.defaultCalendarIdentifier else {
                return ToolOutcome(text: "No writable calendar is available.")
            }
            let minutes = min(max(Self.number(arguments["minutes"]) ?? 60, 5), 24 * 60)
            var draft = EventDraft.new(on: start, calendarIdentifier: calendarID, calendar: calendarService.calendar)
            draft.title = title
            draft.start = start
            draft.end = start.addingTimeInterval(minutes * 60)
            draft.isAllDay = false
            // Writing to the user's calendar is not something a model does
            // silently: the form opens prefilled and the user presses Save.
            calendarService.pendingDraft = draft
            calendarService.startCreating(on: start)
            // Bring the calendar module forward so the form is actually seen.
            NotificationCenter.default.post(name: .hotzShowModule, object: nil, userInfo: ["tab": NotchTab.calendar.rawValue])
            return ToolOutcome(text: "Opened a new event \"\(title)\" at \(Self.dateTimeFormatter.string(from: start)) for the user to confirm. Do not claim it is saved.")

        case "now_playing":
            guard let track = services.mediaCenter.track else {
                return ToolOutcome(text: "Nothing is playing.")
            }
            let state = track.isPlaying ? "playing" : "paused"
            return ToolOutcome(text: "\(track.title) — \(track.artist) (\(state)).")

        case "today_events":
            let events = services.calendarService.events(forDay: Date())
            guard !events.isEmpty else { return ToolOutcome(text: "No events today.") }
            let lines = events.map { event in
                event.isAllDay
                    ? "all day — \(event.title)"
                    : "\(Self.eventTimeFormatter.string(from: event.start))–\(Self.eventTimeFormatter.string(from: event.end)) \(event.title)"
            }
            return ToolOutcome(text: lines.joined(separator: "\n"))

        case "create_note":
            guard let text = (arguments["text"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return .failure("'text' is required.")
            }
            services.notesStore.quickCapture(text)
            return ToolOutcome(text: "Note saved.")

        case "unread_emails":
            let mail = services.emailService
            guard mail.config != nil else { return ToolOutcome(text: "Mail is not set up in the widget.") }
            let unread = mail.cachedMessages.filter(\.isUnread).prefix(10)
            guard !unread.isEmpty else { return ToolOutcome(text: "No unread emails.") }
            return ToolOutcome(text: unread.map(Self.describe).joined(separator: "\n"))

        case "search_email":
            let mail = services.emailService
            guard mail.config != nil else { return ToolOutcome(text: "Mail is not set up in the widget.") }
            guard let query = (arguments["query"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
                return .failure("'query' is required.")
            }
            let hits = Self.matches(query, in: mail.cachedMessages).prefix(10)
            mail.search(query)
            NotificationCenter.default.post(name: .hotzShowModule, object: nil, userInfo: ["tab": NotchTab.email.rawValue])
            if hits.isEmpty {
                return ToolOutcome(text: "Nothing cached matches \"\(query)\"; a server search is running in the Mail module.")
            }
            return ToolOutcome(text: "Matches for \"\(query)\" (server search also opened in Mail):\n" + hits.map(Self.describe).joined(separator: "\n"))

        case "open_email":
            let mail = services.emailService
            guard mail.config != nil else { return ToolOutcome(text: "Mail is not set up in the widget.") }
            guard let query = (arguments["query"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
                return .failure("'query' is required.")
            }
            guard let match = Self.matches(query, in: mail.cachedMessages).first else {
                return ToolOutcome(text: "No email matches \"\(query)\".")
            }
            mail.open(match)
            NotificationCenter.default.post(name: .hotzShowModule, object: nil, userInfo: ["tab": NotchTab.email.rawValue])
            return ToolOutcome(text: "Opened: \(Self.describe(match))")

        case "open_note":
            guard let title = (arguments["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return .failure("'title' is required.")
            }
            let notes = services.notesStore
            let match = notes.notes.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }
                ?? notes.notes.first { $0.title.range(of: title, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            guard let match else {
                let names = notes.notes.prefix(10).map(\.title).joined(separator: ", ")
                return ToolOutcome(text: names.isEmpty ? "There are no notes yet." : "No note matches \"\(title)\". Notes: \(names).")
            }
            notes.open(match)
            NotificationCenter.default.post(name: .hotzShowModule, object: nil, userInfo: ["tab": NotchTab.notes.rawValue])
            return ToolOutcome(text: "Opened note \"\(match.title)\".")

        case "append_note":
            guard let text = (arguments["text"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return .failure("'text' is required.")
            }
            let notes = services.notesStore
            guard let open = notes.openNote else {
                notes.quickCapture(text)
                return ToolOutcome(text: "No note was open; saved the text as a new note.")
            }
            let separator = notes.editorText.isEmpty ? "" : (notes.editorText.hasSuffix("\n") ? "" : "\n")
            notes.editorText += separator + text
            notes.editorChanged()
            return ToolOutcome(text: "Added to \"\(open.title)\".")

        case "list_playbooks":
            let all = playbooks.playbooks
            guard !all.isEmpty else { return ToolOutcome(text: "The user has no playbooks yet.") }
            let lines = all.map { playbook -> String in
                var parts: [String] = []
                if !playbook.openBundleIDs.isEmpty { parts.append("opens \(playbook.openBundleIDs.count) app(s)") }
                if playbook.closeOthers { parts.append("closes other apps") }
                if let shortcut = playbook.shortcutName { parts.append("runs shortcut \"\(shortcut)\"") }
                if let minutes = playbook.timerMinutes { parts.append("starts a \(minutes)-minute timer") }
                return "- \(playbook.name): " + (parts.isEmpty ? "does nothing yet" : parts.joined(separator: ", "))
            }
            return ToolOutcome(text: lines.joined(separator: "\n"))

        case "unread_email_count":
            guard services.emailService.config != nil else {
                return ToolOutcome(text: "Mail is not set up in the widget.")
            }
            return ToolOutcome(text: "\(services.emailService.unreadCount) unread emails.")

        default:
            return .failure("Unknown tool \"\(name)\".")
        }
    }

    /// The confirmed half of `run_playbook`.
    func runPlaybook(_ playbook: Playbook) {
        log.info("tool run_playbook confirmed")
        services.playbookRunner.run(playbook)
    }

    // MARK: - Argument helpers

    /// "Frank Greeff — Invitation: … (Tue 15:00)".
    private static func describe(_ message: EmailMessage) -> String {
        let when = dateTimeFormatter.string(from: message.date)
        let subject = message.subject.isEmpty ? "(no subject)" : message.subject
        return "\(message.isUnread ? "• " : "")\(message.fromName) — \(subject) (\(when))"
    }

    /// Every word of the query must appear in the sender or the subject.
    private static func matches(_ query: String, in messages: [EmailMessage]) -> [EmailMessage] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        return messages.filter { message in
            let haystack = (message.fromName + " " + message.fromAddress + " " + message.subject).lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return formatter
    }()

    /// "today", "tomorrow", "yesterday" or YYYY-MM-DD → local midnight.
    private static func parseDay(_ text: String) -> Date? {
        let calendar = Calendar.current
        switch text.trimmingCharacters(in: .whitespaces).lowercased() {
        case "today": return calendar.startOfDay(for: Date())
        case "tomorrow": return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
        case "yesterday": return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))
        default:
            let parts = text.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
    }

    /// YYYY-MM-DDTHH:MM (or with a space) in local time.
    private static func parseDateTime(_ text: String) -> Date? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "T")
        let halves = cleaned.split(separator: "T", maxSplits: 1).map(String.init)
        guard halves.count == 2, let day = parseDay(halves[0]) else { return nil }
        let time = halves[1].split(separator: ":").compactMap { Int($0) }
        guard time.count >= 2 else { return nil }
        return Calendar.current.date(bySettingHour: time[0], minute: time[1], second: 0, of: day)
    }

    private static let eventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func decode(_ json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }

    /// Models send numbers as Int, Double or even quoted strings.
    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as Double: number
        case let number as Int: Double(number)
        case let text as String: Double(text)
        default: nil
        }
    }

    private static func shortValue(_ value: Any) -> String {
        switch value {
        case let text as String: text.count > 40 ? "\"\(text.prefix(40))…\"" : "\"\(text)\""
        case let number as Double where number == number.rounded(): String(Int(number))
        default: "\(value)"
        }
    }
}
