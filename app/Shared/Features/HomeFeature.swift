/// Continue watching, then the rows of the user's sources, then the add-ons' catalog rows.
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
        case markWatched(MediaID)
    }

    enum Effect: Equatable, Sendable {
        /// Start both once, when the store is created.
        case observeContinueWatching
        case observeBoard
        case loadMore(CatalogID)
        case removeFromContinueWatching(MediaID)
        case markWatched(MediaID)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch event {
        case .continueWatchingChanged(let items):
            state.continueWatching = items
            return []
        case .boardChanged(let board):
            state.board = board.sourcesFirst
            return []
        case .loadMore(let id):
            guard case .rows(let rows) = state.board, let row = rows.first(where: { $0.id == id }),
                  row.canLoadMore, row.items.isSettled
            else { return [] }
            return [.loadMore(id)]
        case .removeFromContinueWatching(let media):
            guard state.continueWatching.contains(where: { $0.media == media }) else { return [] }
            return [.removeFromContinueWatching(media)]
        case .markWatched(let media):
            guard state.continueWatching.contains(where: { $0.media == media && $0.canBeMarkedWatched }) else { return [] }
            return [.markWatched(media)]
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
        case .markWatched(let media):
            do {
                try dependencies.library.setWatched(.title(media), true)
            } catch {
                Log.features.error("marking \(media) watched failed: \(error)")
            }
        }
    }
}

extension Board {
    /// The user's own media leads: the sources' rows, then the add-ons', each in core's order.
    /// Core lists sources after the add-ons, which also orders streams and subtitles, so only the
    /// board reorders.
    var sourcesFirst: Board {
        guard case .rows(let rows) = self else { return self }
        return .rows(rows.filter { $0.name.source != nil } + rows.filter { $0.name.source == nil })
    }
}

extension ContinueWatchingItem {
    /// A movie is marked as a whole. Marking a series as a whole would leave the episode in
    /// progress unmarked, so a series is marked on its page instead.
    var canBeMarkedWatched: Bool { type == .movie }
}

extension HomeFeature.State {
    /// The title the hero shows: the first one with wide artwork, else the first one, of the rows
    /// that have loaded. A source's rows come first and often have no wide artwork.
    var featured: MetaPreview? {
        guard case .rows(let rows) = board else { return nil }
        let loaded = rows.lazy.compactMap(\.items.value).joined()
        return loaded.first { $0.background != nil } ?? loaded.first
    }

    /// Where to start `video`: the saved position when continue watching holds this exact video.
    func resumePosition(for video: PlayableID) -> Duration? {
        guard case .partway(let offset, _)? = continueWatching.first(where: { $0.video == video })?.reason else { return nil }
        return offset
    }

    /// The continue watching entry for a title the user stopped partway through, to offer Resume on its page.
    func progress(of media: MediaID) -> ContinueWatchingItem? {
        continueWatching.first { item in
            guard item.media == media, case .partway = item.reason else { return false }
            return true
        }
    }
}
