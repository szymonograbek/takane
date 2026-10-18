/// Continue watching and the add-ons' catalog rows.
enum HomeFeature: Feature {
    struct Dependencies: Sendable {
        let library: any LibraryService
        let catalog: any CatalogService
    }

    struct State: Equatable, Sendable {
        var continueWatching: [ContinueWatchingItem] = []
        var board = Board.loading
    }

    enum Event: Sendable {
        case continueWatchingChanged([ContinueWatchingItem])
        case boardChanged(Board)
        /// Sent when the end of a row comes into view.
        case loadMore(CatalogID)
        case removeFromContinueWatching(MediaID)
    }

    enum Effect: Equatable, Sendable {
        /// Start both once, when the store is created.
        case observeContinueWatching
        case observeBoard
        case loadMore(CatalogID)
        case removeFromContinueWatching(MediaID)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch event {
        case .continueWatchingChanged(let items):
            state.continueWatching = items
            return []
        case .boardChanged(let board):
            state.board = board
            return []
        case .loadMore(let id):
            guard case .rows(let rows) = state.board, let row = rows.first(where: { $0.id == id }),
                  row.canLoadMore, row.items.isSettled
            else { return [] }
            return [.loadMore(id)]
        case .removeFromContinueWatching(let media):
            guard state.continueWatching.contains(where: { $0.media == media }) else { return [] }
            return [.removeFromContinueWatching(media)]
        }
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        switch effect {
        case .observeContinueWatching:
            for await items in dependencies.library.continueWatching() {
                send(.continueWatchingChanged(items))
            }
        case .observeBoard:
            for await board in dependencies.catalog.board() {
                send(.boardChanged(board))
            }
        case .loadMore(let id):
            dependencies.catalog.loadMore(id)
        case .removeFromContinueWatching(let media):
            dependencies.library.removeFromContinueWatching(media)
        }
    }
}

extension HomeFeature.State {
    /// The title the hero shows: the first one with wide artwork in the first row that has loaded.
    var featured: MetaPreview? {
        guard case .rows(let rows) = board else { return nil }
        let loaded = rows.lazy.compactMap(\.items.value).first { !$0.isEmpty }
        return loaded?.first { $0.background != nil } ?? loaded?.first
    }

    /// Where to start `video`: the saved position when continue watching holds this exact video.
    func resumePosition(for video: PlayableID) -> Duration? {
        continueWatching.first { $0.video == video }?.offset
    }

    /// The continue watching entry for a title, to offer Resume on its page.
    func progress(of media: MediaID) -> ContinueWatchingItem? {
        continueWatching.first { $0.media == media }
    }
}
