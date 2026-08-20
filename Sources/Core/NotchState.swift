import Foundation

/// Island states. `.compact` is reserved for the "always visible indicators"
/// mode — it activates together with the first module.
enum NotchState: Equatable {
    case closed
    case compact
    case expanded
}
