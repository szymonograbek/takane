/// One catalog's titles in one genre, for the screen that lists them.
enum GenreFeature: Feature {
    struct Dependencies: Sendable {
        let catalog: any CatalogService
    }

    enum State: Equatable, Sendable {
        case loading(GenreFilter)
        /// Empty when the catalog has nothing in the genre.
        case loaded(GenreFilter, [MetaPreview])
        case failed(GenreFilter, CatalogError)
    }

    enum Event: Sendable {
        case titlesChanged(GenreFilter, Remote<[MetaPreview], CatalogError>)
        case retry
    }

    enum Effect: Equatable, Sendable {
        /// Start it when the store is created. It follows the titles' changes.
        case load(GenreFilter)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state, event) {
        case (_, .titlesChanged(let filter, let titles)) where filter == state.filter:
            state = switch titles {
            case .loading: .loading(filter)
            case .loaded(let previews): .loaded(filter, previews)
            case .failed(let error): .failed(filter, error)
            }
            return []
        case (.failed(let filter, _), .retry):
            state = .loading(filter)
            return [.load(filter)]
        case (.loaded(let filter, let previews), .retry) where previews.isEmpty:
            state = .loading(filter)
            return [.load(filter)]
        case (_, .titlesChanged), (.loading, .retry), (.loaded, .retry):
            return []
        }
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        switch effect {
        case .load(let filter):
            for await titles in dependencies.catalog.titles(filter) {
                send(.titlesChanged(filter, titles))
            }
        }
    }

    static func key(_ effect: Effect) -> AnyHashable? {
        switch effect {
        case .load: "load"
        }
    }
}

extension GenreFeature.State {
    var filter: GenreFilter {
        switch self {
        case .loading(let filter), .loaded(let filter, _), .failed(let filter, _): filter
        }
    }
}
