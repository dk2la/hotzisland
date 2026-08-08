import Foundation

/// A user-defined scenario: one tap rearranges the workspace — closes apps,
/// opens apps, switches Focus (via Shortcuts) and starts a timer.
struct Playbook: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    /// SF Symbol shown on the playbook button.
    var icon: String = "bolt.fill"
    /// Bundle IDs to open (and to keep when `closeOthers` is on).
    var openBundleIDs: [String] = []
    /// Close every regular app that is not part of this playbook.
    var closeOthers = false
    /// Name of a Shortcuts shortcut to run (e.g. one that sets a Focus).
    var shortcutName: String?
    /// Start the island's timer for this many minutes.
    var timerMinutes: Int?
}

/// Outcome of a playbook run, for logging and the confirmation event.
struct PlaybookRunResult: Equatable {
    var closed = 0
    var opened = 0
    var failures: [String] = []
}
