import Foundation
import Observation

/// One unit of app behavior as a finite state machine.
///
/// `reduce` is the only place state changes and holds every rule (legal transitions, stale
/// results, throttling), so tests drive it without async code or fakes. `run` performs the
/// effects `reduce` asked for against the feature's services and reports back as events.
protocol Feature {
    associatedtype State: Equatable & Sendable
    associatedtype Event: Sendable
    associatedtype Effect: Equatable & Sendable
    associatedtype Dependencies: Sendable

    /// Pure. An event that makes no sense in the current state leaves it unchanged and returns no effects.
    static func reduce(_ state: inout State, _ event: Event) -> [Effect]

    /// Performs one effect. Long-lived effects (subscriptions) run until cancelled.
    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async

    /// Effects with the same key replace each other: starting one cancels the one still running.
    /// Nil, the default, runs alongside every other effect.
    static func key(_ effect: Effect) -> AnyHashable?
}

extension Feature {
    static func key(_ effect: Effect) -> AnyHashable? { nil }
}

/// Runs a `Feature` for SwiftUI: holds its state, reduces events and runs effects.
///
/// Effects start in the order `reduce` returned them, each in its own main-actor task.
/// An effect whose order matters relative to another belongs in one effect.
@MainActor
@Observable
final class FeatureStore<F: Feature> {
    private(set) var state: F.State

    @ObservationIgnored private let dependencies: F.Dependencies
    @ObservationIgnored private var effects: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var keyedEffects: [AnyHashable: UUID] = [:]
    @ObservationIgnored private var waiters: [UUID: (F.State) -> Bool] = [:]

    /// - Parameter start: effects to run immediately, such as subscriptions the feature always needs.
    init(_ state: F.State, dependencies: F.Dependencies, start: [F.Effect] = []) {
        self.state = state
        self.dependencies = dependencies
        start.forEach(run)
    }

    deinit {
        effects.values.forEach { $0.cancel() }
    }

    func send(_ event: F.Event) {
        let effects = F.reduce(&state, event)
        Log.features.trace("\(F.self) \(event) → \(state)")
        effects.forEach(run)
        waiters = waiters.filter { _, isResolved in !isResolved(state) }
    }

    /// Waits until `probe` decides, re-checking after every event. For tests and the smoke test.
    func until<Value: Sendable, Failure: Error & Sendable>(
        timeout: Duration,
        onTimeout: Failure,
        _ probe: @escaping (F.State) -> Probe<Value, Failure>
    ) async throws(Failure) -> Value {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Value, Failure>, Never>) in
            let resolve = { (state: F.State) -> Bool in
                switch probe(state) {
                case .pending: return false
                case .done(let value): continuation.resume(returning: .success(value))
                case .failed(let failure): continuation.resume(returning: .failure(failure))
                }
                return true
            }
            guard !resolve(state) else { return }
            let id = UUID()
            waiters[id] = resolve
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                if self?.waiters.removeValue(forKey: id) != nil {
                    continuation.resume(returning: .failure(onTimeout))
                }
            }
        }
        return try result.get()
    }

    private func run(_ effect: F.Effect) {
        let id = UUID()
        if let key = F.key(effect) {
            if let running = keyedEffects[key] { effects[running]?.cancel() }
            keyedEffects[key] = id
        }
        let dependencies = dependencies
        effects[id] = Task { [weak self] in
            await F.run(effect, dependencies) { event in self?.send(event) }
            self?.effects[id] = nil
        }
    }
}
