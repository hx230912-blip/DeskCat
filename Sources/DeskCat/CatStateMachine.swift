import Foundation

enum CatState: String, CaseIterable {
    case idle, alert, carry, walk, throwing, happy, error
}

/// Keeps visual states independent from file-system outcomes.
@MainActor
final class CatStateMachine {
    private(set) var state: CatState = .idle
    var onChange: ((CatState) -> Void)?
    private var pendingReset: Task<Void, Never>?

    func transition(to newState: CatState, resetAfter seconds: Double? = nil) {
        pendingReset?.cancel()
        state = newState
        onChange?(newState)
        if let seconds {
            pendingReset = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.transition(to: .idle)
            }
        }
    }
}
