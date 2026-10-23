/// Looks up streams for one item at a time, and for signed-out accounts where else the title can be
/// watched.
enum StreamsFeature: Feature {
    struct Dependencies: Sendable {
        let streams: any StreamService
        let offers: any WatchOfferService
    }

    enum State: Equatable, Sendable {
        case idle
        /// `results` is nil until the first answer arrives. `offers` is nil when not looked up.
        case lookingUp(PlayableID, results: StreamResults?, offers: Remote<[WatchOffer], WatchOfferError>?)
    }

    enum Event: Sendable {
        /// `account` decides whether offers are looked up too.
        case lookUp(PlayableID, account: Account)
        case resultsChanged(StreamResults)
        case offersFound(PlayableID, Result<[WatchOffer], WatchOfferError>)
    }

    enum Effect: Equatable, Sendable {
        case watch(PlayableID)
        case findOffers(PlayableID)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state, event) {
        case (_, .lookUp(let item, let account)):
            let findsOffers = account == .anonymous
            state = .lookingUp(item, results: nil, offers: findsOffers ? .loading : nil)
            return findsOffers ? [.watch(item), .findOffers(item)] : [.watch(item)]
        case (.lookingUp(let item, _, let offers), .resultsChanged(let results)) where results.item == item:
            state = .lookingUp(item, results: results, offers: offers)
            return []
        case (.lookingUp(let item, let results, .loading), .offersFound(let answered, let found)) where answered == item:
            switch found {
            case .success(let offers): state = .lookingUp(item, results: results, offers: .loaded(offers))
            case .failure(let error): state = .lookingUp(item, results: results, offers: .failed(error))
            }
            return []
        case (.idle, .resultsChanged), (.lookingUp, .resultsChanged), (.idle, .offersFound), (.lookingUp, .offersFound):
            // Answers for an item no longer looked up.
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
        case .findOffers(let item):
            do {
                send(.offersFound(item, .success(try await dependencies.offers.offers(for: item.media))))
            } catch {
                send(.offersFound(item, .failure(error)))
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
        if case .lookingUp(_, let results, _) = self { results?.isComplete != true } else { false }
    }

    /// Sources that answered with streams, in add-on order.
    var loadedSources: [LoadedSource] {
        guard case .lookingUp(_, let results?, _) = self else { return [] }
        return results.sources.compactMap { source in
            source.candidates.value.map { LoadedSource(addon: source.addon, addonName: source.addonName, candidates: $0) }
        }
    }

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .lookingUp(_, let results, _):
            guard let results, results.isComplete else { return "Loading…" }
            let sources = loadedSources
            return "\(sources.map(\.candidates.count).reduce(0, +)) streams from \(sources.count) add-ons"
        }
    }
}
