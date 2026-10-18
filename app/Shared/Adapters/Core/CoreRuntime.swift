import Foundation
import os

enum CoreRequestError<Failure: Error & Sendable>: Error, Sendable {
    case rejected(CoreError)
    case timedOut
    case failed(Failure)
}

/// Turns core's protocol (dispatch an action, later receive `NewState` for the fields it changed)
/// into async streams and results. The core adapters' only handle on core.
final class CoreRuntime: Sendable {
    private struct Subscriber: Sendable {
        let field: CoreField
        let refresh: @Sendable () -> Void
    }

    private let client: CoreClient
    private let subscribers = OSAllocatedUnfairLock<[UUID: Subscriber]>(initialState: [:])

    private init(client: CoreClient) {
        self.client = client
    }

    /// Starts core and loads persisted state from `storageDirectory`.
    static func start(storageDirectory: URL) async throws(CoreError) -> CoreRuntime {
        let started = await Task.detached(priority: .userInitiated) { () -> Result<CoreClient, CoreError> in
            Result { () throws(CoreError) in try CoreClient.start(storageDirectory: storageDirectory) }
        }.value
        let runtime = CoreRuntime(client: try started.get())
        let changes = runtime.client.changes
        Task.detached { [weak runtime] in
            for await fields in changes {
                runtime?.notify(fields)
            }
            Log.core.warning("core change stream ended")
        }
        return runtime
    }

    func dispatch(_ action: CoreAction, to field: CoreField? = nil) throws(CoreError) {
        try client.dispatch(action, to: field)
    }

    func state<State: Decodable>(_ field: CoreField, as type: State.Type = State.self) throws(CoreError) -> State {
        try client.state(field)
    }

    /// The field's state now, then after every change.
    func states<State: Decodable & Sendable>(_ field: CoreField, as type: State.Type = State.self) -> AsyncStream<State> {
        stream(of: field, removingDuplicates: { _, _ in false }, read: { client throws(CoreError) in
            try client.state(field, as: State.self)
        })
    }

    /// `transform` of the field's state now, then after every change that alters it.
    func observe<State: Decodable, Value: Equatable & Sendable>(
        _ field: CoreField,
        as type: State.Type = State.self,
        _ transform: @escaping @Sendable (State) -> Value
    ) -> AsyncStream<Value> {
        stream(of: field, removingDuplicates: ==, read: { client throws(CoreError) in
            transform(try client.state(field, as: State.self))
        })
    }

    /// Dispatches `action` to `target` and waits until `probe` accepts a state of `field`.
    /// The current state is probed first, so a probe must check it answers this request,
    /// not an earlier one.
    func request<State: Decodable & Sendable, Value: Sendable, Failure: Error & Sendable>(
        _ action: CoreAction,
        to target: CoreField?,
        observing field: CoreField,
        as type: State.Type = State.self,
        timeout: Duration,
        until probe: @escaping @Sendable (State) -> Probe<Value, Failure>
    ) async throws(CoreRequestError<Failure>) -> Value {
        // Subscribing before dispatching means no change is missed.
        let states = states(field, as: State.self)
        do {
            try dispatch(action, to: target)
        } catch {
            throw .rejected(error)
        }
        let outcome = await withTaskGroup(of: Result<Value, CoreRequestError<Failure>>?.self) { group in
            group.addTask {
                for await state in states {
                    switch probe(state) {
                    case .pending: continue
                    case .done(let value): return .success(value)
                    case .failed(let failure): return .failure(.failed(failure))
                    }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .failure(.timedOut)
            }
            defer { group.cancelAll() }
            for await case let outcome? in group {
                return outcome
            }
            return .failure(.timedOut)
        }
        return try outcome.get()
    }

    private func stream<Value: Sendable>(
        of field: CoreField,
        removingDuplicates isDuplicate: @escaping @Sendable (Value, Value) -> Bool,
        read: @escaping @Sendable (CoreClient) throws(CoreError) -> Value
    ) -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream.makeStream(of: Value.self, bufferingPolicy: .bufferingNewest(1))
        let client = client
        // Reading under the lock keeps yields in the order core produced the states.
        let latest = OSAllocatedUnfairLock<Value?>(initialState: nil)
        let refresh: @Sendable () -> Void = {
            latest.withLock { latest in
                let value: Value
                do {
                    value = try read(client)
                } catch {
                    Log.core.error("reading \(field.rawValue) failed: \(error)")
                    return
                }
                if let latest, isDuplicate(latest, value) { return }
                latest = value
                continuation.yield(value)
            }
        }
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.subscribers.withLock { $0[id] = nil }
        }
        subscribers.withLock { $0[id] = Subscriber(field: field, refresh: refresh) }
        refresh()
        return stream
    }

    private func notify(_ fields: [CoreField]) {
        let affected = subscribers.withLock { subscribers in
            subscribers.values.filter { fields.contains($0.field) }
        }
        affected.forEach { $0.refresh() }
    }
}
