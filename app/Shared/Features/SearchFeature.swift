/// Searches the add-ons as the user types.
enum SearchFeature: Feature {
    struct Dependencies: Sendable {
        let catalog: any CatalogService
        /// How long typing has to pause before a search starts.
        var settle = Duration.milliseconds(400)
    }

    enum State: Equatable, Sendable {
        case empty
        /// `results` is nil until the provider answers this query.
        case searching(SearchText, results: SearchResults?)
    }

    enum Event: Sendable {
        case queryChanged(SearchText?)
        case resultsChanged(SearchResults)
    }

    enum Effect: Equatable, Sendable {
        case search(SearchText)
        /// Stops the running search, when the query is cleared.
        case cancelSearch
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state, event) {
        case (_, .queryChanged(nil)):
            state = .empty
            return [.cancelSearch]
        case (.searching(let current, _), .queryChanged(let text?)) where current == text:
            return []
        case (_, .queryChanged(let text?)):
            state = .searching(text, results: nil)
            return [.search(text)]
        case (.searching(let text, _), .resultsChanged(let results)) where results.text == text || results == .noSearchAddons:
            state = .searching(text, results: results)
            return []
        case (.empty, .resultsChanged), (.searching, .resultsChanged):
            return []
        }
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        switch effect {
        case .search(let text):
            // A newer query cancels this one, during the pause or while results stream in.
            guard (try? await Task.sleep(for: dependencies.settle)) != nil else { return }
            for await results in dependencies.catalog.search(text) {
                send(.resultsChanged(results))
            }
        case .cancelSearch:
            break
        }
    }

    static func key(_ effect: Effect) -> AnyHashable? {
        switch effect {
        case .search, .cancelSearch: "search"
        }
    }
}

extension SearchResults {
    /// The query these results answer, nil when no add-on can search.
    var text: SearchText? {
        switch self {
        case .searching(let text), .rows(let text, _): text
        case .noSearchAddons: nil
        }
    }
}
