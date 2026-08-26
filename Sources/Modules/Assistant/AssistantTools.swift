import Foundation
import OSLog

/// The assistant's hands: a fixed registry of tools executed on the main
/// actor against the live module services. Declarations follow the OpenAI
/// function-calling schema; results are short English strings the model
/// rephrases in the conversation language.
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

    // MARK: - Declarations

    static let declarations: [[String: Any & Sendable]] = [
        function(
            "set_timer",
            "Start a countdown timer in the widget.",
            parameters: [
                "minutes": ["type": "number", "description": "Duration in minutes (1-240)"],
            ],
            required: ["minutes"]
        ),
        function(
            "run_playbook",
            "Run one of the user's playbooks (opens/closes apps, runs a shortcut) by name.",
            parameters: [
                "name": ["type": "string", "description": "Playbook name, exact or approximate"],
            ],
            required: ["name"]
        ),
        function("now_playing", "What music is currently playing.", parameters: [:], required: []),
        function("today_events", "The user's calendar events for today.", parameters: [:], required: []),
        function(
            "create_note",
            "Save a note to the user's notes folder.",
            parameters: [
                "text": ["type": "string", "description": "Note text; the first line becomes the title"],
            ],
            required: ["text"]
        ),
        function("unread_email_count", "How many unread emails the user has.", parameters: [:], required: []),
    ]

    private static func function(
        _ name: String,
        _ description: String,
        parameters: [String: [String: String]],
        required: [String]
    ) -> [String: Any & Sendable] {
        let schema: [String: Any & Sendable] = [
            "type": "object",
            "properties": parameters,
            "required": required,
        ]
        let function: [String: Any & Sendable] = [
            "name": name,
            "description": description,
            "parameters": schema,
        ]
        return ["type": "function", "function": function]
    }

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

    func execute(name: String, argumentsJSON: String) -> String {
        let arguments = Self.decode(argumentsJSON)
        log.info("tool \(name, privacy: .public)")
        switch name {
        case "set_timer":
            guard let minutes = Self.number(arguments["minutes"]), minutes > 0 else {
                return "Error: 'minutes' must be a positive number."
            }
            let clamped = min(max(minutes, 1), 240)
            services.timerService.setDuration(clamped * 60)
            services.timerService.start()
            return "Timer started for \(Int(clamped)) minutes."

        case "run_playbook":
            guard let query = (arguments["name"] as? String)?
                .trimmingCharacters(in: .whitespaces), !query.isEmpty else {
                return "Error: 'name' is required."
            }
            let all = playbooks.playbooks
            guard !all.isEmpty else { return "The user has no playbooks yet." }
            let match = all.first { $0.name.caseInsensitiveCompare(query) == .orderedSame }
                ?? all.first { $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            guard let match else {
                let names = all.map(\.name).joined(separator: ", ")
                return "No playbook matches \"\(query)\". Available: \(names)."
            }
            services.playbookRunner.run(match)
            return "Playbook \"\(match.name)\" started."

        case "now_playing":
            guard let track = services.mediaCenter.track else {
                return "Nothing is playing."
            }
            let state = track.isPlaying ? "playing" : "paused"
            return "\(track.title) — \(track.artist) (\(state))."

        case "today_events":
            let events = services.calendarService.events(forDay: Date())
            guard !events.isEmpty else { return "No events today." }
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let lines = events.map { event in
                event.isAllDay
                    ? "all day — \(event.title)"
                    : "\(formatter.string(from: event.start))–\(formatter.string(from: event.end)) \(event.title)"
            }
            return lines.joined(separator: "\n")

        case "create_note":
            guard let text = (arguments["text"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return "Error: 'text' is required."
            }
            services.notesStore.quickCapture(text)
            return "Note saved."

        case "unread_email_count":
            guard services.emailService.config != nil else {
                return "Mail is not set up in the widget."
            }
            return "\(services.emailService.unreadCount) unread emails."

        default:
            return "Error: unknown tool \"\(name)\"."
        }
    }

    // MARK: - Argument helpers

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
