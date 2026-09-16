import AppKit
import Foundation

/// One action of a playbook. Steps run in order; each carries its own id so
/// the editor can reorder and remove them without index juggling.
enum PlaybookStep: Codable, Equatable, Sendable, Identifiable {
    /// Launch the apps, then arrange their windows when `layout != .none`.
    case openApps(id: UUID, bundleIDs: [String], layout: WindowLayout)
    /// Politely quit every regular app the playbook does not open itself.
    case closeOtherApps(id: UUID)
    /// Run a Shortcuts shortcut by name.
    case runShortcut(id: UUID, name: String)
    /// Switch Focus through a shortcut that sets it — macOS has no API.
    case setFocus(id: UUID, shortcutName: String)
    /// Start the island's timer for this many minutes.
    case startTimer(id: UUID, minutes: Int)
    /// Open links in their default handlers.
    case openURLs(id: UUID, urls: [String])

    /// The discriminator stored in JSON and the label the editor shows.
    enum Kind: String, Codable, CaseIterable, Sendable {
        case openApps, closeOtherApps, runShortcut, setFocus, startTimer, openURLs

        var icon: String {
            switch self {
            case .openApps: "macwindow.on.rectangle"
            case .closeOtherApps: "xmark.rectangle"
            case .runShortcut: "square.2.layers.3d"
            case .setFocus: "moon.fill"
            case .startTimer: "timer"
            case .openURLs: "link"
            }
        }

        @MainActor
        var title: String {
            switch self {
            case .openApps: L10n.t(.playStepOpenApps)
            case .closeOtherApps: L10n.t(.playStepCloseOthers)
            case .runShortcut: L10n.t(.playStepShortcut)
            case .setFocus: L10n.t(.playStepFocus)
            case .startTimer: L10n.t(.playStepTimer)
            case .openURLs: L10n.t(.playStepURLs)
            }
        }

        /// A fresh, empty step of this kind — what "Add step" inserts.
        func makeStep() -> PlaybookStep {
            switch self {
            case .openApps: .openApps(id: UUID(), bundleIDs: [], layout: .none)
            case .closeOtherApps: .closeOtherApps(id: UUID())
            case .runShortcut: .runShortcut(id: UUID(), name: "")
            case .setFocus: .setFocus(id: UUID(), shortcutName: "")
            case .startTimer: .startTimer(id: UUID(), minutes: 25)
            case .openURLs: .openURLs(id: UUID(), urls: [])
            }
        }
    }

    var id: UUID {
        switch self {
        case .openApps(let id, _, _), .closeOtherApps(let id), .runShortcut(let id, _),
             .setFocus(let id, _), .startTimer(let id, _), .openURLs(let id, _):
            id
        }
    }

    var kind: Kind {
        switch self {
        case .openApps: .openApps
        case .closeOtherApps: .closeOtherApps
        case .runShortcut: .runShortcut
        case .setFocus: .setFocus
        case .startTimer: .startTimer
        case .openURLs: .openURLs
        }
    }

    // MARK: - Codable
    // Flat object with a `kind` discriminator: {"kind":"openApps","id":…,
    // "bundleIDs":[…],"layout":"thirds"}. Keys are explicit so renaming a
    // case never silently breaks saved files.

    private enum CodingKeys: String, CodingKey {
        case kind, id, bundleIDs, layout, name, shortcutName, minutes, urls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        switch kind {
        case .openApps:
            self = .openApps(
                id: id,
                bundleIDs: try container.decodeIfPresent([String].self, forKey: .bundleIDs) ?? [],
                layout: try container.decodeIfPresent(WindowLayout.self, forKey: .layout) ?? .none
            )
        case .closeOtherApps:
            self = .closeOtherApps(id: id)
        case .runShortcut:
            self = .runShortcut(id: id, name: try container.decodeIfPresent(String.self, forKey: .name) ?? "")
        case .setFocus:
            self = .setFocus(
                id: id,
                shortcutName: try container.decodeIfPresent(String.self, forKey: .shortcutName) ?? ""
            )
        case .startTimer:
            self = .startTimer(id: id, minutes: try container.decodeIfPresent(Int.self, forKey: .minutes) ?? 0)
        case .openURLs:
            self = .openURLs(id: id, urls: try container.decodeIfPresent([String].self, forKey: .urls) ?? [])
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(id, forKey: .id)
        switch self {
        case .openApps(_, let bundleIDs, let layout):
            try container.encode(bundleIDs, forKey: .bundleIDs)
            try container.encode(layout, forKey: .layout)
        case .closeOtherApps:
            break
        case .runShortcut(_, let name):
            try container.encode(name, forKey: .name)
        case .setFocus(_, let shortcutName):
            try container.encode(shortcutName, forKey: .shortcutName)
        case .startTimer(_, let minutes):
            try container.encode(minutes, forKey: .minutes)
        case .openURLs(_, let urls):
            try container.encode(urls, forKey: .urls)
        }
    }
}

/// A user-defined scenario: one tap runs an ordered list of steps —
/// close apps, open and arrange apps, switch Focus, start a timer, open
/// links.
struct Playbook: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    /// SF Symbol shown on the playbook button.
    var icon: String = "bolt.fill"
    var steps: [PlaybookStep] = []

    private enum CodingKeys: String, CodingKey {
        case id, name, icon, steps
    }

    init(id: UUID = UUID(), name: String, icon: String = "bolt.fill", steps: [PlaybookStep] = []) {
        self.id = id
        self.name = name
        self.icon = icon
        self.steps = steps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "bolt.fill"
        // Required on purpose: a file without `steps` is the legacy shape
        // and must go through migration, not decode as an empty playbook.
        steps = try container.decode([PlaybookStep].self, forKey: .steps)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode(steps, forKey: .steps)
    }

    // MARK: - Derived

    /// Every app the playbook opens, across all steps, in order, deduped.
    var appBundleIDs: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for case .openApps(_, let bundleIDs, _) in steps {
            for bundleID in bundleIDs where seen.insert(bundleID).inserted {
                result.append(bundleID)
            }
        }
        return result
    }

    /// One short English line per step — what the assistant reads out.
    /// English by design: the model reasons over it, the user does not.
    @MainActor
    var summaryLines: [String] {
        steps.map { step in
            switch step {
            case .openApps(_, let bundleIDs, let layout):
                let names = bundleIDs.map { AppVisuals.name(for: $0) ?? $0 }
                var line = "opens \(bundleIDs.count) app(s)"
                if !names.isEmpty { line += ": " + names.joined(separator: ", ") }
                if layout != .none { line += " (\(layout.englishName))" }
                return line
            case .closeOtherApps:
                return "closes other apps"
            case .runShortcut(_, let name):
                return "runs shortcut \"\(name)\""
            case .setFocus(_, let shortcutName):
                return "sets Focus via shortcut \"\(shortcutName)\""
            case .startTimer(_, let minutes):
                return "starts a \(minutes)-minute timer"
            case .openURLs(_, let urls):
                return "opens \(urls.count) link(s)"
            }
        }
    }
}

extension WindowLayout {
    /// Fixed English name for logs and the assistant, independent of the
    /// interface language (`title` is the localized one).
    var englishName: String {
        switch self {
        case .none: "no layout"
        case .leftRight: "side by side"
        case .thirds: "three columns"
        case .grid2x2: "2x2 grid"
        case .mainAndSide: "main + sidebar"
        case .fullscreen: "fill the screen"
        }
    }
}

/// Outcome of a playbook run, for logging and the confirmation event.
struct PlaybookRunResult: Equatable, Sendable {
    var closed = 0
    var opened = 0
    var failures: [String] = []
}
