/// The library's shows' upcoming episodes, for the calendar screen.
enum CalendarFeature: Feature {
    struct Dependencies: Sendable {
        let library: any LibraryService
    }

    enum State: Equatable, Sendable {
        case loading
        /// Earliest first. Empty when nothing is coming up.
        case loaded([UpcomingEpisode])
        case failed(CatalogError)
    }

    enum Event: Sendable {
        /// The screen appeared. The library may have changed since, so the episodes load again.
        case appeared
        case episodesChanged(Remote<[UpcomingEpisode], CatalogError>)
        case retry
    }

    enum Effect: Equatable, Sendable {
        case load
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state, event) {
        // The episodes shown stay until the new answer replaces them.
        case (.loading, .appeared), (.loaded, .appeared):
            return [.load]
        case (.failed, .appeared), (.failed, .retry):
            state = .loading
            return [.load]
        case (_, .episodesChanged(.loaded(let episodes))):
            state = .loaded(episodes)
            return []
        case (.loading, .episodesChanged(.failed(let error))):
            state = .failed(error)
            return []
        // A reload that fails keeps the episodes it would have replaced.
        case (_, .episodesChanged(.loading)), (.loaded, .episodesChanged(.failed)), (.failed, .episodesChanged(.failed)),
             (.loading, .retry), (.loaded, .retry):
            return []
        }
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        switch effect {
        case .load:
            for await episodes in dependencies.library.upcomingEpisodes() {
                send(.episodesChanged(episodes))
            }
        }
    }

    static func key(_ effect: Effect) -> AnyHashable? {
        switch effect {
        case .load: "load"
        }
    }
}
