/// Looks up streams for one item at a time.
enum StreamsFeature: Feature {
    struct Dependencies: Sendable {
        let streams: any StreamService
    }

    enum State: Equatable, Sendable {
        case idle
        /// `results` is nil until the first answer arrives.
        case lookingUp(PlayableID, results: StreamResults?)
    }

    enum Event: Sendable {
        case lookUp(PlayableID)
        case resultsChanged(StreamResults)
    }

    enum Effect: Equatable, Sendable {
        case watch(PlayableID)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state, event) {
        case (_, .lookUp(let item)):
            state = .lookingUp(item, results: nil)
            return [.watch(item)]
        case (.lookingUp(let item, _), .resultsChanged(let results)) where results.item == item:
            state = .lookingUp(item, results: results)
            return []
        case (.idle, .resultsChanged), (.lookingUp, .resultsChanged):
            // Results for an item no longer looked up.
            return []
        }
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        switch effect {
        case .watch(let item):
            for await results in dependencies.streams.streams(for: item) {
                send(.resultsChanged(results))
            }
        }
    }
}

extension StreamsFeature.State {
    struct LoadedSource: Identifiable, Equatable, Sendable {
        let addon: ManifestURL
        let addonName: Redacted<String>
        let candidates: [StreamCandidate]

        var id: ManifestURL { addon }
    }

    var isLookingUp: Bool {
        if case .lookingUp(_, let results) = self { results?.isComplete != true } else { false }
    }

    /// Sources that answered with streams, in add-on order.
    var loadedSources: [LoadedSource] {
        guard case .lookingUp(_, let results?) = self else { return [] }
        return results.sources.compactMap { source in
            source.candidates.value.map { LoadedSource(addon: source.addon, addonName: source.addonName, candidates: $0) }
        }
    }

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .lookingUp(_, let results):
            guard let results, results.isComplete else { return "Loading…" }
            let sources = loadedSources
            return "\(sources.map(\.candidates.count).reduce(0, +)) streams from \(sources.count) add-ons"
        }
    }
}
