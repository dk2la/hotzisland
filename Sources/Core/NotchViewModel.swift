import Observation

@MainActor
@Observable
final class NotchViewModel {
    private(set) var state: NotchState = .closed

    func setState(_ newState: NotchState) {
        guard newState != state else { return }
        state = newState
    }
}
