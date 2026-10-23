import Foundation

enum CatState: String, CaseIterable {
    case idle, grooming, sleeping, walking, alert, carry, throwing, happy, error
}

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
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.transition(to: .idle)
            }
        }
    }

    func idleActivity() {
        guard [.idle, .grooming, .sleeping].contains(state) else { return }
        let roll = Int.random(in: 0..<100)
        if roll < 18 { transition(to: .grooming, resetAfter: 4) }
        else if roll < 30 { transition(to: .sleeping, resetAfter: 8) }
        else { transition(to: .idle) }
    }
}
