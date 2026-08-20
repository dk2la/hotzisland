import Foundation

/// Transient system events surfaced by the island while it is closed.
enum LiveEvent: Equatable {
    case charging(percent: Int, plugged: Bool)
    case audioDevice(name: String)
    case volume(level: Double)
    case timerFinished
    case playbookRan(name: String)
}
