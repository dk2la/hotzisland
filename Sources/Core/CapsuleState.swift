/// Capsule states. `.compact` is the resting state of the "compact
/// indicators" idle mode: shown while a timer runs or media is playing,
/// `.closed` otherwise (see CapsuleWindowController.idleState). The
/// "invisible" idle mode always rests at `.closed`.
enum CapsuleState: Equatable {
    case closed
    case compact
    case expanded
}
