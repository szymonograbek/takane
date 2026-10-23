/// The Library tab: the titles of the user's library or of one of their sources, for the filter
/// the user picked, paged as they scroll.
enum LibraryFeature: Feature {
    struct Dependencies: Sendable {
        let library: any LibraryService
        let sources: any MediaSourceService
    }

    /// What the picker chooses: the Stremio library, or one of the user's sources.
    enum Collection: Hashable, Sendable {
        case yourLibrary
        case source(SourceID)
    }

    /// What the grid lists: the collection, with its type and order.
    enum Listing: Hashable, Sendable {
        case library(LibraryFilter)
        case source(SourceTitlesFilter)
    }

    /// A source's titles for one filter, as far as they are paged in.
    struct SourceTitles: Equatable, Sendable {
        enum Paging: Equatable, Sendable {
            case complete
            /// The next page starts `skip` titles in.
            case more(skip: Int)
            case loadingMore(skip: Int)
        }

        let filter: SourceTitlesFilter
        /// Each title once, in the filter's order.
        var titles: [MetaPreview]
        var paging: Paging
    }

    enum State: Equatable, Sendable {
        case loading(LibraryFilter)
        case loaded(LibraryContents)
        /// Until the first page of a source's titles answers.
        case loadingSource(SourceTitlesFilter)
        case source(SourceTitles)
        case sourceFailed(SourceTitlesFilter, SourceError)
    }

    enum Event: Sendable {
        /// The picker chose a collection, which opens with its first listing.
        case pick(Collection)
        /// The type or sort menus chose another listing of the collection.
        case select(Listing)
        case contentsChanged(LibraryContents)
        case sourceListed(SourceTitlesFilter, skip: Int, Result<SourceTitlesPage, SourceError>)
        /// The last loaded title came into view.
        case loadMore
        case remove(MediaID)
        case retry
    }

    enum Effect: Equatable, Sendable {
        /// It follows the contents' changes until another listing replaces it.
        case observe(LibraryFilter)
        case listSource(SourceTitlesFilter, skip: Int)
        case loadMore
        case remove(MetaPreview)
    }

    /// Every type, most recently watched first.
    static let defaultFilter = LibraryFilter(type: nil, sort: .recentlyWatched)

    /// The state and effects that open `collection`, for the store to start with.
    static func opening(_ collection: Collection) -> (state: State, effects: [Effect]) {
        var state = State.loading(defaultFilter)
        let effects = show(collection.firstListing, in: &state)
        return (state, effects)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state, event) {
        case (_, .pick(let collection)) where collection != state.listing.collection:
            return show(collection.firstListing, in: &state)
        case (_, .select(let listing)) where listing != state.listing:
            return show(listing, in: &state)
        case (_, .contentsChanged(let contents)) where state.listing == .library(contents.filter):
            state = .loaded(contents)
            return []
        case (.loadingSource(let filter), .sourceListed(let answered, skip: 0, let result)) where answered == filter:
            state = switch result {
            case .success(let page): .source(SourceTitles(filter: filter, titles: [], paging: .complete).adding(page, from: 0))
            case .failure(let error): .sourceFailed(filter, error)
            }
            return []
        case (.source(var titles), .sourceListed(let answered, let skip, let result))
            where answered == titles.filter && titles.paging == .loadingMore(skip: skip):
            switch result {
            case .success(let page): titles = titles.adding(page, from: skip)
            // Scrolling to the end again asks again.
            case .failure: titles.paging = .more(skip: skip)
            }
            state = .source(titles)
            return []
        case (.loaded(let contents), .loadMore) where contents.canLoadMore:
            return [.loadMore]
        case (.source(var titles), .loadMore):
            guard case .more(let skip) = titles.paging else { return [] }
            titles.paging = .loadingMore(skip: skip)
            state = .source(titles)
            return [.listSource(titles.filter, skip: skip)]
        case (.loaded(let contents), .remove(let media)):
            return contents.titles.first { $0.media == media }.map { [.remove($0)] } ?? []
        case (.sourceFailed(let filter, _), .retry):
            state = .loadingSource(filter)
            return [.listSource(filter, skip: 0)]
        case (_, .pick), (_, .select), (_, .contentsChanged), (_, .sourceListed),
             (.loading, .loadMore), (.loaded, .loadMore), (.loadingSource, .loadMore), (.sourceFailed, .loadMore),
             (.loading, .remove), (.loadingSource, .remove), (.source, .remove), (.sourceFailed, .remove),
             (.loading, .retry), (.loaded, .retry), (.loadingSource, .retry), (.source, .retry):
            return []
        }
    }

    private static func show(_ listing: Listing, in state: inout State) -> [Effect] {
        switch listing {
        case .library(let filter):
            state = .loading(filter)
            return [.observe(filter)]
        case .source(let filter):
            state = .loadingSource(filter)
            return [.listSource(filter, skip: 0)]
        }
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        switch effect {
        case .observe(let filter):
            for await contents in dependencies.library.library(filter) {
                send(.contentsChanged(contents))
            }
        case .listSource(let filter, let skip):
            do throws(SourceError) {
                send(.sourceListed(filter, skip: skip, .success(try await dependencies.sources.titles(filter, skip: skip))))
            } catch {
                send(.sourceListed(filter, skip: skip, .failure(error)))
            }
        case .loadMore:
            dependencies.library.loadMoreLibrary()
        case .remove(let title):
            dependencies.library.setInLibrary(title, false)
        }
    }

    /// A new listing stops following the one before.
    static func key(_ effect: Effect) -> AnyHashable? {
        switch effect {
        case .observe, .listSource: "listing"
        case .loadMore, .remove: nil
        }
    }
}

extension LibraryFeature.Collection {
    /// Your Library opens as it always does; a source opens with everything it has, newest first.
    var firstListing: LibraryFeature.Listing {
        switch self {
        case .yourLibrary: .library(LibraryFeature.defaultFilter)
        case .source(let source): .source(SourceTitlesFilter(source: source, type: nil, sort: .recentlyAdded))
        }
    }
}

extension LibraryFeature.Listing {
    var collection: LibraryFeature.Collection {
        switch self {
        case .library: .yourLibrary
        case .source(let filter): .source(filter.source)
        }
    }
}

extension LibraryFeature.SourceTitles {
    /// With `page`, which starts `skip` titles in, after the titles already listed. A title a page
    /// before listed, as when the source changed between pages, stays where it first showed.
    func adding(_ page: SourceTitlesPage, from skip: Int) -> Self {
        var seen = Set(titles.map(\.media))
        let added = page.titles.filter { seen.insert($0.media).inserted }
        return Self(filter: filter, titles: titles + added, paging: page.hasMore ? .more(skip: skip + page.titles.count) : .complete)
    }
}

extension LibraryFeature.State {
    var listing: LibraryFeature.Listing {
        switch self {
        case .loading(let filter): .library(filter)
        case .loaded(let contents): .library(contents.filter)
        case .loadingSource(let filter), .sourceFailed(let filter, _): .source(filter)
        case .source(let titles): .source(titles.filter)
        }
    }
}
