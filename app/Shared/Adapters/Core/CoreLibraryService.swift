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
