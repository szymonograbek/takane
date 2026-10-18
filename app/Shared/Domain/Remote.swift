/// A value fetched from somewhere slow and fallible.
enum Remote<Value: Sendable & Equatable, Failure: Error & Sendable & Equatable>: Sendable, Equatable {
    case loading
    case loaded(Value)
    case failed(Failure)

    var value: Value? {
        if case .loaded(let value) = self { value } else { nil }
    }

    var isSettled: Bool {
        if case .loading = self { false } else { true }
    }
}

/// One look at changing state while waiting for an outcome.
enum Probe<Value, Failure: Error> {
    case pending
    case done(Value)
    case failed(Failure)
}
