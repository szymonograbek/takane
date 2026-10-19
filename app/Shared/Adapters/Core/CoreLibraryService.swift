import Foundation

/// Core's library: continue watching, the `library` model's titles and the `calendar` model's
/// episodes. Core holds one library filter, so a newer `library(_:)` call finishes the older stream.
struct CoreLibraryService: LibraryService {
    let runtime: CoreRuntime

    func continueWatching() -> AsyncStream<[ContinueWatchingItem]> {
        runtime.observe(.continueWatchingPreview, as: ContinueWatchingState.self) { state in
            state.items.compactMap(Self.item)
        }
    }

    func removeFromContinueWatching(_ media: MediaID) {
        runtime.dispatchLogged(.ctx(.rewindLibraryItem(id: media.rawValue)))
        runtime.dispatchLogged(.ctx(.dismissNotificationItem(id: media.rawValue)))
    }

    func library(_ filter: LibraryFilter) -> AsyncStream<LibraryContents> {
        let request = LibraryRequest(filter)
        return runtime.load(.libraryWithFilters(request), into: .library) { (state: LibraryState) in
            guard state.selected?.request == request else { return nil }
            return LibraryContents(
                filter: filter,
                types: state.selectable.types.compactMap { $0.type.flatMap(ContentType.init) },
                titles: state.catalog.compactMap(Self.preview),
                canLoadMore: state.selectable.nextPage != nil
            )
        }
    }

    func loadMoreLibrary() {
        runtime.dispatchLogged(.library(.loadNextPage), to: .library)
    }

    func setInLibrary(_ title: MetaPreview, _ isInLibrary: Bool) {
        runtime.dispatchLogged(.ctx(isInLibrary ? .addToLibrary(title) : .removeFromLibrary(id: title.media.rawValue)))
    }

    func upcomingEpisodes() -> AsyncStream<Remote<[UpcomingEpisode], CatalogError>> {
        // Dispatch is synchronous, so the load below sees the calendar unloaded, not the earlier answer.
        runtime.dispatchLogged(.unload, to: .calendar)
        return runtime.load(.calendar, into: .calendar, pending: .loading) { (state: CalendarState) in
            state.upcomingEpisodes(from: Calendar.current.startOfDay(for: .now))
        }
    }

    func checkForNewEpisodes() {
        runtime.dispatchLogged(.ctx(.pullNotifications))
    }

    /// Core marks through the `meta_details` model's library item, which exists for a loaded title
    /// before the library holds it. A title it does not hold is marked through the library.
    func setWatched(_ target: WatchedTarget, _ isWatched: Bool) throws(WatchedError) {
        let page: MetaDetailsState
        do {
            page = try runtime.state(.metaDetails)
        } catch {
            throw .unavailable(reason: "\(error)")
        }
        let metaItem = page.selected.flatMap { selected in
            selected.metaPath.id == target.media.rawValue ? page.metaItem(at: selected.metaPath) : nil
        }
        let action: CoreAction
        switch (target, metaItem) {
        case (.title, .some):
            action = .metaDetails(.markAsWatched(isWatched))
        case (.title(let media), .none):
            action = .ctx(.libraryItemMarkAsWatched(id: media.rawValue, isWatched: isWatched))
        case (.season(_, let season), .some(let metaItem)):
            guard let number = UInt32(exactly: season), metaItem.videos.contains(where: { $0.season == season }) else {
                throw .notFound
            }
            action = .metaDetails(.markSeasonAsWatched(number, isWatched))
        case (.video(let playable), .some(let metaItem)):
            guard let video = metaItem.videos.first(where: { $0.id == playable.rawValue }) else { throw .notFound }
            action = .metaDetails(.markVideoAsWatched(video: video.raw, isWatched))
        case (.season, .none), (.video, .none):
            throw .titleNotLoaded
        }
        do {
            try runtime.dispatch(action, to: metaItem == nil ? nil : .metaDetails)
        } catch {
            throw .unavailable(reason: "\(error)")
        }
    }

    private static func preview(_ item: LibraryItem) -> MetaPreview? {
        guard let media = MediaID(item.id), let type = ContentType(item.type) else { return nil }
        let poster = item.poster.flatMap(URL.init(string:))
        return MetaPreview(
            media: media, type: type, name: item.name, poster: poster, posterShape: PosterShape(core: item.posterShape),
            background: poster.flatMap(background), logo: nil, releaseInfo: nil, description: nil
        )
    }

    private static func item(_ entry: ContinueWatchingState.Item) -> ContinueWatchingItem? {
        let item = entry.library
        guard let media = MediaID(item.id), let type = ContentType(item.type),
              let reason = reason(item.state, newEpisodes: entry.notifications)
        else { return nil }
        let poster = item.poster.flatMap(URL.init(string:))
        return ContinueWatchingItem(
            media: media,
            type: type,
            name: item.name,
            poster: poster,
            background: poster.flatMap(background),
            video: item.state.videoId.flatMap(PlayableID.init) ?? .movie(media),
            reason: reason
        )
    }

    /// Core lists an item for its progress or, with none, for new episodes.
    private static func reason(_ state: LibraryItem.State, newEpisodes: Int) -> ContinueWatchingItem.Reason? {
        if state.timeOffset > 0 {
            return .partway(offset: .milliseconds(state.timeOffset), duration: .milliseconds(state.duration))
        }
        return newEpisodes > 0 ? .newEpisodes(count: newEpisodes) : nil
    }

    /// Cinemeta's posters come from Stremio's image service, which serves the same title's wide
    /// artwork under `background` (`…/poster/medium/tt…/img` → `…/background/medium/tt…/img`).
    private static func background(forPoster poster: URL) -> URL? {
        guard poster.host() == "images.metahub.space", poster.pathComponents.count > 1, poster.pathComponents[1] == "poster" else { return nil }
        var components = poster.pathComponents.dropFirst()
        components[components.startIndex] = "background"
        return URL(string: "https://images.metahub.space/" + components.joined(separator: "/"))
    }
}
