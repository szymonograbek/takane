import Foundation

extension CalendarState {
    /// The episodes released at or after `start`, earliest first, once every add-on answered. Nil
    /// while core holds no calendar.
    func upcomingEpisodes(from start: Date) -> Remote<[UpcomingEpisode], CatalogError>? {
        guard selected != nil else { return nil }
        var shows: [Show] = []
        var hasAnswer = false
        var failure: CatalogError?
        for resource in metaItems {
            switch resource.content {
            case .none, .loading: return .loading
            case .ready(let content): shows += content; hasAnswer = true
            case .failed(let error) where error == .emptyContent: hasAnswer = true
            case .failed(let error): failure = .addonFailed(reason: error.compactDescription)
            }
        }
        if !hasAnswer, let failure { return .failed(failure) }
        // Two add-ons may list the same show; an episode shows once.
        var seen = Set<PlayableID>()
        let episodes = shows.flatMap { show in Self.episodes(of: show, from: start) }
            .filter { seen.insert($0.video).inserted }
            .sorted { ($0.released, $0.show.name, $0.video.rawValue) < ($1.released, $1.show.name, $1.video.rawValue) }
        return .loaded(episodes)
    }

    private static func episodes(of show: Show, from start: Date) -> [UpcomingEpisode] {
        guard let media = MediaID(show.id), let type = ContentType(show.type) else { return [] }
        let preview = MetaPreview(
            media: media, type: type, name: show.name,
            poster: show.poster.flatMap(URL.init(string:)), posterShape: PosterShape(core: show.posterShape),
            background: show.background.flatMap(URL.init(string:)), logo: show.logo.flatMap(URL.init(string:)),
            releaseInfo: nil, description: nil
        )
        return show.videos.compactMap { video in
            guard let playable = PlayableID(video.id), case .episode = playable, let released = video.released.flatMap(Date.init(core:)),
                  released >= start
            else { return nil }
            return UpcomingEpisode(show: preview, video: playable, name: video.title, released: released)
        }
    }
}
