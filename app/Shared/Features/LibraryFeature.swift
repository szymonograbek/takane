/// The library's titles for the filter the user picked, for the screen that lists them.
enum LibraryFeature: Feature {
    struct Dependencies: Sendable {
        let library: any LibraryService
    }

    enum State: Equatable, Sendable {
        case loading(LibraryFilter)
        case loaded(LibraryContents)
    }

    enum Event: Sendable {
        case select(LibraryFilter)
        case contentsChanged(LibraryContents)
        /// The last loaded title came into view.
        case loadMore
        case remove(MediaID)
    }

    enum Effect: Equatable, Sendable {
        /// Start it when the store is created. It follows the contents' changes.
        case observe(LibraryFilter)
        case loadMore
        case remove(MetaPreview)
    }

    /// Every type, most recently watched first.
    static let defaultFilter = LibraryFilter(type: nil, sort: .recentlyWatched)

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state, event) {
        case (_, .select(let filter)) where filter != state.filter:
            state = .loading(filter)
            return [.observe(filter)]
        case (_, .contentsChanged(let contents)) where contents.filter == state.filter:
            state = .loaded(contents)
            return []
        case (.loaded(let contents), .loadMore) where contents.canLoadMore:
            return [.loadMore]
        case (.loaded(let contents), .remove(let media)):
            return contents.titles.first { $0.media == media }.map { [.remove($0)] } ?? []
        case (_, .select), (_, .contentsChanged), (.loading, .loadMore), (.loaded, .loadMore), (.loading, .remove):
            return []
        }
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        switch effect {
        case .observe(let filter):
            for await contents in dependencies.library.library(filter) {
                send(.contentsChanged(contents))
            }
        case .loadMore:
            dependencies.library.loadMoreLibrary()
        case .remove(let title):
            dependencies.library.setInLibrary(title, false)
        }
    }

    static func key(_ effect: Effect) -> AnyHashable? {
        switch effect {
        case .observe: "observe"
        case .loadMore, .remove: nil
        }
    }
}

extension LibraryFeature.State {
    var filter: LibraryFilter {
        switch self {
        case .loading(let filter): filter
        case .loaded(let contents): contents.filter
        }
    }
}
