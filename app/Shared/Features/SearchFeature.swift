/// Searches the add-ons as the user types, suggesting recent searches that continue the query.
/// Before anything is typed, offers recent searches.
enum SearchFeature: Feature {
    struct Dependencies: Sendable {
        let catalog: any CatalogService
        /// How long typing has to pause before a search starts.
        var settle = Duration.milliseconds(400)
    }

    struct State: Equatable, Sendable {
        /// Most recent first, without the steps of typing another one (see `recentSearches(_:)`).
        /// Nil until the provider answers.
        var recentSearches: [SearchText]?
        var query = Query.empty
    }

    enum Query: Equatable, Sendable {
        case empty
        /// `results` is nil until the provider answers this query.
        case searching(SearchText, results: SearchResults?)
    }

    enum Event: Sendable {
        case queryChanged(SearchText?)
        case resultsChanged(SearchResults)
        case recentSearchesChanged([SearchText])
        case clearRecentSearches
    }

    enum Effect: Equatable, Sendable {
        /// Start it once, when the store is created.
        case observeRecentSearches
        case search(SearchText)
        /// Stops the running search, when the query is cleared.
        case cancelSearch
        case clearRecentSearches
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state.query, event) {
        case (_, .queryChanged(nil)):
            state.query = .empty
            return [.cancelSearch]
        case (.searching(let current, _), .queryChanged(let text?)) where current == text:
            return []
        case (_, .queryChanged(let text?)):
            state.query = .searching(text, results: nil)
            return [.search(text)]
        case (.searching(let text, _), .resultsChanged(let results)) where results.text == text || results == .noSearchAddons:
            state.query = .searching(text, results: results)
            return []
        case (.empty, .resultsChanged), (.searching, .resultsChanged):
            return []
        case (_, .recentSearchesChanged(let searches)):
            state.recentSearches = recentSearches(searches)
            return []
        case (.empty, .clearRecentSearches) where state.recentSearches?.isEmpty == false:
            return [.clearRecentSearches]
        case (.empty, .clearRecentSearches), (.searching, .clearRecentSearches):
            return []
        }
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        switch effect {
        case .observeRecentSearches:
            for await searches in dependencies.catalog.recentSearches() {
                send(.recentSearchesChanged(searches))
            }
        case .search(let text):
            // A newer query cancels this one, during the pause or while results stream in.
            guard (try? await Task.sleep(for: dependencies.settle)) != nil else { return }
            for await results in dependencies.catalog.search(text) {
                send(.resultsChanged(results))
            }
        case .cancelSearch:
            break
        case .clearRecentSearches:
            dependencies.catalog.clearRecentSearches()
        }
    }

    static func key(_ effect: Effect) -> AnyHashable? {
        switch effect {
        case .search, .cancelSearch: "search"
        case .observeRecentSearches, .clearRecentSearches: nil
        }
    }

    /// Searching as the user types records every pause, so the provider's history holds "bre" on
    /// the way to "breaking bad" and "breaking ba" on the way back. A search that another one
    /// continues is such a step and is left out, as is a repeat in other letter case.
    private static func recentSearches(_ searches: [SearchText]) -> [SearchText] {
        var kept: [SearchText] = []
        for search in searches {
            let isStep = searches.contains { $0.continuation(of: search) != nil }
            let isRepeat = kept.contains { $0.rawValue.caseInsensitiveCompare(search.rawValue) == .orderedSame }
            if !isStep && !isRepeat { kept.append(search) }
        }
        return kept
    }
}

/// A recent search that continues what is typed.
struct SearchSuggestion: Hashable, Sendable {
    let search: SearchText
    /// The start of `search` that matches what was typed, in the search's own letter case.
    let typed: Substring
    let completion: Substring
}

extension SearchFeature.State {
    /// Up to four recent searches that continue the query, most recent first.
    var suggestions: [SearchSuggestion] {
        guard case .searching(let text, _) = query else { return [] }
        let matches = (recentSearches ?? []).compactMap { search in
            search.continuation(of: text).map { end in
                SearchSuggestion(search: search, typed: search.rawValue[..<end], completion: search.rawValue[end...])
            }
        }
        return Array(matches.prefix(4))
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
