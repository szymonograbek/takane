import Foundation

/// Continue watching as core's library holds it.
struct CoreLibraryService: LibraryService {
    let runtime: CoreRuntime

    func continueWatching() -> AsyncStream<[ContinueWatchingItem]> {
        runtime.observe(.continueWatchingPreview, as: ContinueWatchingState.self) { state in
            state.items.compactMap(Self.item)
        }
    }

    func removeFromContinueWatching(_ media: MediaID) {
        runtime.dispatchLogged(.ctx(.rewindLibraryItem(id: media.rawValue)))
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

    private static func item(_ item: LibraryItem) -> ContinueWatchingItem? {
        guard let media = MediaID(item.id), let type = ContentType(item.type) else { return nil }
        let poster = item.poster.flatMap(URL.init(string:))
        return ContinueWatchingItem(
            media: media,
            type: type,
            name: item.name,
            poster: poster,
            background: poster.flatMap(background),
            video: item.state.videoId.flatMap(PlayableID.init) ?? .movie(media),
            offset: .milliseconds(item.state.timeOffset),
            duration: .milliseconds(item.state.duration)
        )
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
