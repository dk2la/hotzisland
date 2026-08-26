import Foundation
import OSLog

/// What one tool run produced. Typed, because sniffing an "Error:" prefix
/// would break the moment a tool result legitimately starts with that word.
struct ToolOutcome {
    var text: String
    var isError = false

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
        ToolSpec(name: "now_playing", description: "What music is currently playing.", exampleArguments: "{}"),
        ToolSpec(name: "today_events", description: "The user's calendar events for today.", exampleArguments: "{}"),
        ToolSpec(
            name: "create_note",
            description: "Save a note to the user's notes folder.",
            exampleArguments: #"{"text": "buy milk"}"#,
            parameters: ["text": ["type": "string", "description": "Note text; the first line becomes the title"]],
            required: ["text"]
        ),
        ToolSpec(name: "unread_email_count", description: "How many unread emails the user has.", exampleArguments: "{}"),
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
            services.timerService.setDuration(clamped * 60)
            services.timerService.start()
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
            services.playbookRunner.run(match)
            return ToolOutcome(text: "Playbook \"\(match.name)\" started.")

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

        case "unread_email_count":
            guard services.emailService.config != nil else {
                return ToolOutcome(text: "Mail is not set up in the widget.")
            }
            return ToolOutcome(text: "\(services.emailService.unreadCount) unread emails.")

        default:
            return .failure("Unknown tool \"\(name)\".")
        }
    }

    // MARK: - Argument helpers

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
