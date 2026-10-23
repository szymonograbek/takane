import Foundation

/// Catalogs and metadata from the user's add-ons through core's `board`, `search`, `discover` and
/// `meta_details` models, and recent searches from its search history.
///
/// Core holds one selection per model. A new search replaces the previous one and finishes its
/// stream. `details` shares `meta_details` with `CoreStreamService`: it replaces a running stream
/// lookup, and a stream lookup for the same title (an episode's show) reuses the metadata it loaded.
struct CoreCatalogService: CatalogService {
    let runtime: CoreRuntime

    func board() -> AsyncStream<Board> {
        loadCatalogs(.board, into: .board, pending: Board.loading) { state, addons in
            state.catalogs.isEmpty ? .noCatalogAddons : .rows(Self.rows(state, addons: addons, paging: true))
        }
    }

    func loadMore(_ row: CatalogID) {
        do {
            let state = try runtime.state(.board, as: CatalogsState.self)
            guard let index = state.catalogs.firstIndex(where: { $0.first.flatMap { Self.catalogID($0.request) } == row }) else {
                Log.core.warning("no board row \(row.addon) \(row.type)/\(row.id) to load more of")
                return
            }
            try runtime.dispatch(.catalogs(.loadNextPage(index: index)), to: .board)
        } catch {
            Log.core.error("loading more of \(row.type)/\(row.id) failed: \(error)")
        }
    }

    func search(_ text: SearchText) -> AsyncStream<SearchResults> {
        loadCatalogs(.search(text), into: .search, pending: SearchResults.searching(text)) { state, addons in
            state.catalogs.isEmpty ? .noSearchAddons : .rows(text, Self.rows(state, addons: addons, paging: false))
        }
    }

    func recentSearches() -> AsyncStream<[SearchText]> {
        // Core records every search the `search` model loads.
        runtime.observe(.ctx, as: CtxState.self) { $0.searchHistory.compactMap(SearchText.init) }
    }

    func clearRecentSearches() {
        runtime.dispatchLogged(.ctx(.clearSearchHistory))
    }

    func genres() -> AsyncStream<[CatalogGenres]> {
        runtime.observe(.ctx, as: CtxState.self) { state in
            state.answeringAddons.flatMap { addon in
                addon.manifest.catalogs.compactMap { catalog -> CatalogGenres? in
                    // A catalog that requires the extra lists other values under it, such as Cinemeta's years.
                    guard let addonURL = ManifestURL(addon.transportUrl), let type = ContentType(catalog.type),
                          let extra = catalog.extra.first(where: { $0.name == "genre" && !$0.isRequired })
                    else { return nil }
                    let genres = extra.options.compactMap(Genre.init)
                    guard !genres.isEmpty else { return nil }
                    return CatalogGenres(catalog: CatalogID(addon: addonURL, type: type, id: Redacted(catalog.id)), genres: genres)
                }
            }
        }
    }

    func titles(_ filter: GenreFilter) -> AsyncStream<Remote<[MetaPreview], CatalogError>> {
        let request = ResourceRequest(
            base: filter.catalog.addon.url.rawValue,
            path: .catalog(type: filter.catalog.type.rawValue, id: filter.catalog.id.rawValue, extra: [["genre", filter.genre.rawValue]])
        )
        return runtime.load(.catalogWithFilters(request), into: .discover, pending: .loading) { (state: CatalogWithFiltersState) in
            state.selected?.request == request ? Self.items(state.catalog) : nil
        }
    }

    func details(_ media: MediaID, type: ContentType) async throws(DetailsError) -> TitleDetails {
        let metaPath = ResourcePath.meta(type: type.rawValue, id: media.rawValue)
        do {
            return try await runtime.request(
                .core(.load(.metaDetails(metaPath: metaPath, streamPath: nil)), to: .metaDetails), observing: .metaDetails,
                as: MetaDetailsState.self, timeout: .seconds(30)
            ) { details -> Probe<TitleDetails, DetailsError> in
                guard details.selected?.metaPath == metaPath else { return .pending }
                // Core asks every add-on with the `meta` resource for this type and id; none means none installed.
                guard !details.metaItems.isEmpty else { return .failed(.noMetaAddons) }
                if let item = details.metaItem(at: metaPath) {
                    return Self.details(item, in: details).map(Probe.done) ?? .failed(.notFound)
                }
                return details.metaItems.allSatisfy { $0.content?.isSettled ?? false } ? .failed(.notFound) : .pending
            }
        } catch {
            switch error {
            case .rejected(let error): throw .unavailable(reason: "\(error)")
            case .timedOut: throw .unavailable(reason: "timed out")
            case .failed(let error): throw error
            }
        }
    }

    func detailsChanges(_ media: MediaID, type: ContentType) -> AsyncStream<TitleDetails> {
        let metaPath = ResourcePath.meta(type: type.rawValue, id: media.rawValue)
        let states = runtime.observe(.metaDetails, as: MetaDetailsState.self) { state in
            state.metaItem(at: metaPath).flatMap { Self.details($0, in: state) }
        }
        let (values, continuation) = AsyncStream.makeStream(of: TitleDetails.self, bufferingPolicy: .bufferingNewest(1))
        let task = Task {
            for await case let details? in states {
                continuation.yield(details)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return values
    }

    /// Loads `selection` into the `CatalogsWithExtra` model `field`, as `CoreRuntime.load` does, and requests
    /// every catalog core lists.
    private func loadCatalogs<Value: Sendable>(
        _ selection: CatalogsSelection,
        into field: CoreField,
        pending: Value,
        _ transform: @escaping @Sendable (CatalogsState, [Addon]) -> Value
    ) -> AsyncStream<Value> {
        let runtime = runtime
        return runtime.load(.catalogsWithExtra(selection), into: field, pending: pending) { (state: CatalogsState) in
            guard state.selected == selection else { return nil }
            // Core lists catalogs without requesting them, on load and when add-ons change.
            if state.catalogs.contains(where: { $0.first?.content == nil }) {
                do {
                    try runtime.dispatch(.catalogs(.loadRange(0..<state.catalogs.count)), to: field)
                } catch {
                    Log.core.error("requesting \(field.rawValue) catalogs rejected: \(error)")
                }
            }
            return transform(state, Self.addons(runtime))
        }
    }

    private static func addons(_ runtime: CoreRuntime) -> [Addon] {
        do {
            return try runtime.state(.ctx, as: CtxState.self).answeringAddons
        } catch {
            Log.core.error("reading addons failed: \(error)")
            return []
        }
    }

    private static func catalogID(_ request: ResourceRequest) -> CatalogID? {
        guard let addon = ManifestURL(request.base), let type = ContentType(request.path.type) else { return nil }
        return CatalogID(addon: addon, type: type, id: Redacted(request.path.id))
    }

    private static func rows(_ state: CatalogsState, addons: [Addon], paging: Bool) -> [CatalogRow] {
        state.catalogs.compactMap { pages in
            guard let first = pages.first, let id = catalogID(first.request),
                  let addon = addons.first(where: { $0.transportUrl == first.request.base }),
                  let catalog = addon.manifest.catalogs.first(where: { $0.id == id.id.rawValue && $0.type == id.type.rawValue })
            else { return nil }
            // Core's own rule for `LoadNextPage`: the last page loaded and the catalog accepts `skip`.
            let canLoadMore = paging && pages.last?.content?.readyContent != nil && catalog.extraNames.contains("skip")
            return CatalogRow(
                id: id, addonName: addon.manifest.name, name: catalog.name.map(Redacted.init) ?? addon.manifest.name,
                items: items(pages), canLoadMore: canLoadMore
            )
        }
    }

    /// The titles of a catalog's pages, as its first page stands.
    private static func items(_ pages: [ResourceLoadable<[MetaItemPreview]>]) -> Remote<[MetaPreview], CatalogError> {
        switch pages.first?.content {
        case .none, .loading: .loading
        case .failed(let error) where error == .emptyContent: .loaded([])
        case .failed(let error): .failed(.addonFailed(reason: error.compactDescription))
        case .ready: .loaded(previews(pages))
        }
    }

    private static func previews(_ pages: [ResourceLoadable<[MetaItemPreview]>]) -> [MetaPreview] {
        // Pages may overlap; a title shows once, where it first appeared.
        var seen = Set<MediaID>()
        return pages.compactMap { $0.content?.readyContent }.joined().compactMap(preview).filter { seen.insert($0.media).inserted }
    }

    private static func preview(_ item: MetaItemPreview) -> MetaPreview? {
        guard let media = MediaID(item.id), let type = ContentType(item.type) else { return nil }
        return MetaPreview(
            media: media, type: type, name: Redacted(item.name),
            poster: item.poster.flatMap(URL.init(string:)), posterShape: PosterShape(core: item.posterShape),
            background: item.background.flatMap(URL.init(string:)), logo: item.logo.flatMap(URL.init(string:)),
            releaseInfo: item.releaseInfo.map(Redacted.init), description: item.description.map(Redacted.init)
        )
    }

    private static func details(_ item: MetaDetailsState.MetaItem, in state: MetaDetailsState) -> TitleDetails? {
        guard let preview = preview(item.preview) else { return nil }
        return TitleDetails(
            preview: preview,
            genres: item.preview.links.filter { $0.category == "Genres" }.map(\.name),
            runtime: item.preview.runtime,
            imdbRating: item.preview.links.first { $0.category == "imdb" }?.name,
            videos: item.videos.compactMap { video in
                PlayableID(video.id).map { playable in
                    Video(
                        playable: playable, name: Redacted(video.title), season: video.season, episode: video.episode,
                        released: video.released.flatMap(Date.init(core:)), thumbnail: video.thumbnail.flatMap(URL.init(string:)),
                        overview: video.overview.map(Redacted.init), isWatched: state.watchedVideos.contains(video.id)
                    )
                }
            },
            isWatched: (state.libraryItem?.state.timesWatched ?? 0) > 0,
            isInLibrary: state.libraryItem?.isInLibrary ?? false,
            rating: rating(state.ratingInfo)
        )
    }

    private static func rating(_ info: Loadable<MetaDetailsState.RatingInfo>?) -> RatingStatus {
        switch info {
        case nil: .unavailable
        case .loading: .loading
        case .ready(let info): .rated(info.status.flatMap(TitleRating.init(core:)))
        case .failed: .failed
        }
    }
}
