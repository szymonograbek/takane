import Foundation

/// A Jellyfin server this device is signed in to, as one source.
struct JellyfinServer: Sendable {
    let source: SourceID
    let endpoint: SourceEndpoint
    let session: JellyfinSession
}

/// A report Jellyfin keeps the user's resume position and watched state by.
struct JellyfinPlaybackReport: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case started
        case progress
        case stopped
    }

    let kind: Kind
    let source: SourceID
    let item: SourceItemID
    let file: SourceItemID
    /// Ties the reports of one playback together.
    let playSession: String
    let position: Duration
    let isPaused: Bool
}

/// What a Jellyfin source offers: its libraries, its files and their subtitles, and where it plays
/// them from. API calls carry the token in the `Authorization` header, as the server refuses it in
/// the query there; the player's requests carry it the same way, so no URL holds it.
extension JellyfinClient {
    /// Library kinds that hold films, shows or videos. Music, books, photos, playlists and box sets,
    /// which repeat films listed elsewhere, are left out.
    private static let videoLibraries: Set<String?> = ["movies", "tvshows", "homevideos", "mixed", nil]

    /// Lists every video library and its titles: one request for the libraries, one per library.
    func index(of server: JellyfinServer) async throws(SourceError) -> SourceIndex {
        let views = try await get(Listing<View>.self, "Users/\(server.session.userID)/Views", [], on: server).items
        var libraries: [(View, [Item])] = []
        for view in views where Self.videoLibraries.contains(view.collectionType) {
            let items = try await get(Listing<Item>.self, "Items", [
                URLQueryItem(name: "userId", value: server.session.userID),
                URLQueryItem(name: "ParentId", value: view.id),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "IncludeItemTypes", value: "Movie,Series,Episode,Video"),
                URLQueryItem(name: "Fields", value: "ProviderIds,Overview,ProductionYear,PremiereDate,PrimaryImageAspectRatio"),
                URLQueryItem(name: "SortBy", value: "DateCreated,SortName"),
                URLQueryItem(name: "SortOrder", value: "Descending"),
                URLQueryItem(name: "EnableUserData", value: "false"),
            ], on: server).items
            libraries.append((view, items))
        }
        return IndexBuilder(server: server).index(libraries)
    }

    /// The files of `items`, in their order, with the subtitle files beside them.
    func files(of items: [SourceItemID], on server: JellyfinServer) async throws(SourceError) -> [SourceFile] {
        guard !items.isEmpty else { return [] }
        let found = try await get(Listing<FileItem>.self, "Items", [
            URLQueryItem(name: "userId", value: server.session.userID),
            URLQueryItem(name: "Ids", value: items.map(\.rawValue).joined(separator: ",")),
            URLQueryItem(name: "Fields", value: "MediaSources"),
            URLQueryItem(name: "EnableImages", value: "false"),
            URLQueryItem(name: "EnableUserData", value: "false"),
        ], on: server).items
        return items.flatMap { id in found.first { $0.id == id.rawValue }?.files ?? [] }
    }

    /// The file as the server sends it unchanged: direct play, no transcoding.
    func video(_ item: SourceItemID, file: SourceItemID, on server: JellyfinServer) -> PlaybackSource {
        let url = server.endpoint.url.rawValue.appending(path: "Videos/\(item)/stream")
            .appending(queryItems: [URLQueryItem(name: "static", value: "true"), URLQueryItem(name: "mediaSourceId", value: file.rawValue)])
        return PlaybackSource(url: Redacted(url), headers: playbackHeaders(server))
    }

    /// A subtitle file as SubRip, which the server converts it to.
    func subtitle(_ item: SourceItemID, file: SourceItemID, index: Int, on server: JellyfinServer) -> PlaybackSource {
        let url = server.endpoint.url.rawValue.appending(path: "Videos/\(item)/\(file)/Subtitles/\(index)/Stream.srt")
        return PlaybackSource(url: Redacted(url), headers: playbackHeaders(server))
    }

    func report(_ report: JellyfinPlaybackReport, to server: JellyfinServer) async throws(SourceError) {
        let path = switch report.kind {
        case .started: "Sessions/Playing"
        case .progress: "Sessions/Playing/Progress"
        case .stopped: "Sessions/Playing/Stopped"
        }
        var request = URLRequest(url: server.endpoint.url.rawValue.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorization(server), forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(PlaybackInfo(report))
        try await signedIn(request)
    }

    private func playbackHeaders(_ server: JellyfinServer) -> [String: String] {
        ["Authorization": authorization(server)]
    }

    private func authorization(_ server: JellyfinServer) -> String {
        authorization(for: server.source, token: server.session.token)
    }

    private func get<Value: Decodable>(
        _ type: Value.Type, _ path: String, _ query: [URLQueryItem], on server: JellyfinServer
    ) async throws(SourceError) -> Value {
        var request = URLRequest(url: server.endpoint.url.rawValue.appending(path: path).appending(queryItems: query))
        request.setValue(authorization(server), forHTTPHeaderField: "Authorization")
        return try await signedIn(request, type)
    }
}

/// Turns Jellyfin's listings into an index: a title is known by its IMDb id when the server has
/// one, else by a local id; an episode plays under its show's id.
private struct IndexBuilder {
    let server: JellyfinServer

    func index(_ libraries: [(View, [Item])]) -> SourceIndex {
        var items: [PlayableID: [SourceItemID]] = [:]
        var localTitles: [MediaID: SourceTitle] = [:]
        let built = libraries.compactMap { view, listed -> SourceIndex.Library? in
            guard let id = SourceItemID(view.id) else { return nil }
            let shows = Dictionary(listed.filter { $0.type == "Series" }.map { ($0.id, $0) }) { first, _ in first }
            var episodes: [String: [SourceEpisode]] = [:]
            for episode in listed where episode.type == "Episode" {
                guard let showID = episode.seriesID, let show = shows[showID], let showMedia = media(of: show),
                      let season = episode.parentIndexNumber, let number = episode.indexNumber, let file = SourceItemID(episode.id)
                else { continue }
                items[.episode(showMedia, season: season, episode: number), default: []].append(file)
                episodes[showID, default: []].append(SourceEpisode(
                    season: season, episode: number, name: Redacted(episode.name), overview: episode.overview.map(Redacted.init),
                    thumbnail: image(episode, "Primary").map(Redacted.init), released: episode.premiereDate
                ))
            }
            let titles = listed.compactMap { item -> SourceTitle? in
                guard let kind = item.kind, let title = title(item, kind, episodes: episodes[item.id] ?? []) else { return nil }
                if kind == .movie, let file = SourceItemID(item.id) {
                    items[.movie(title.id), default: []].append(file)
                }
                if !title.id.rawValue.hasPrefix("tt") {
                    localTitles[title.id] = title
                }
                return title
            }
            return SourceIndex.Library(id: id, name: Redacted(view.name), type: view.collectionType == "tvshows" ? .series : .movie, titles: titles)
        }
        return SourceIndex(libraries: built, items: items, localTitles: localTitles)
    }

    private func title(_ item: Item, _ kind: SourceTitle.Kind, episodes: [SourceEpisode]) -> SourceTitle? {
        guard let id = media(of: item) else { return nil }
        let isMatched = id.rawValue.hasPrefix("tt")
        let poster = isMatched ? URL(string: "https://images.metahub.space/poster/medium/\(id.rawValue)/img") : image(item, "Primary")
        return SourceTitle(
            id: id,
            kind: kind,
            name: Redacted(item.name),
            poster: poster.map(Redacted.init),
            isLandscape: !isMatched && (item.primaryImageAspectRatio ?? 0) > 1,
            background: isMatched ? nil : image(item, "Backdrop").map(Redacted.init),
            overview: item.overview.map(Redacted.init),
            year: item.productionYear,
            episodes: episodes.sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
        )
    }

    /// The IMDb id, or `takane-<source>-<item>`.
    private func media(of item: Item) -> MediaID? {
        if let imdb = item.providerIDs?.imdb, imdb.hasPrefix("tt"), let id = MediaID(imdb) {
            return id
        }
        guard let key = SourceItemID(item.id) else { return nil }
        return MediaID("\(SourceAddonDescriptor.localIDPrefix)\(server.source.rawValue)-\(key)")
    }

    /// Jellyfin's artwork, which it serves without a token.
    private func image(_ item: Item, _ type: String) -> URL? {
        let tag = type == "Backdrop" ? item.backdropImageTags?.first : item.imageTags?[type]
        guard let tag else { return nil }
        let path = type == "Backdrop" ? "Items/\(item.id)/Images/Backdrop/0" : "Items/\(item.id)/Images/\(type)"
        return server.endpoint.url.rawValue.appending(path: path)
            .appending(queryItems: [URLQueryItem(name: "tag", value: tag), URLQueryItem(name: "maxHeight", value: "720")])
    }
}

private struct Listing<Item: Decodable>: Decodable {
    let items: [Item]

    private enum CodingKeys: String, CodingKey { case items = "Items" }
}

private struct View: Decodable {
    let id: String
    let name: String
    let collectionType: String?

    private enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", collectionType = "CollectionType"
    }
}

private struct Item: Decodable {
    struct ProviderIDs: Decodable {
        let imdb: String?

        private enum CodingKeys: String, CodingKey { case imdb = "Imdb" }
    }

    let id: String
    let name: String
    let type: String
    let providerIDs: ProviderIDs?
    let overview: String?
    let productionYear: Int?
    let premiereDate: String?
    let seriesID: String?
    let parentIndexNumber: Int?
    let indexNumber: Int?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let primaryImageAspectRatio: Double?

    /// What a catalog lists it as. Nil for an episode, which its show lists.
    var kind: SourceTitle.Kind? {
        switch type {
        case "Movie", "Video": .movie
        case "Series": .series
        default: nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", type = "Type", providerIDs = "ProviderIds", overview = "Overview"
        case productionYear = "ProductionYear", premiereDate = "PremiereDate", seriesID = "SeriesId"
        case parentIndexNumber = "ParentIndexNumber", indexNumber = "IndexNumber", imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags", primaryImageAspectRatio = "PrimaryImageAspectRatio"
    }
}

/// An item with its files, Jellyfin's media sources.
private struct FileItem: Decodable {
    struct MediaSource: Decodable {
        let id: String
        let name: String?
        let path: String?
        let size: Int?
        let mediaStreams: [MediaStream]?

        private enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", path = "Path", size = "Size", mediaStreams = "MediaStreams"
        }
    }

    struct MediaStream: Decodable {
        let type: String
        let index: Int
        let isExternal: Bool
        let language: String?
        let displayTitle: String?

        private enum CodingKeys: String, CodingKey {
            case type = "Type", index = "Index", isExternal = "IsExternal", language = "Language", displayTitle = "DisplayTitle"
        }
    }

    let id: String
    let mediaSources: [MediaSource]?

    var files: [SourceFile] {
        guard let item = SourceItemID(id) else { return [] }
        return (mediaSources ?? []).compactMap { source in
            guard let file = SourceItemID(source.id) else { return nil }
            let streams = source.mediaStreams ?? []
            // The stream's own subtitles are the player's to list; these are files beside it.
            let subtitles = streams.filter { $0.type == "Subtitle" && $0.isExternal }.map { stream in
                SourceSubtitle(index: stream.index, language: stream.language, label: Redacted(stream.displayTitle ?? stream.language ?? "Subtitles"))
            }
            let name = source.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? source.name ?? ""
            return SourceFile(
                item: item, file: file, name: Redacted(name), quality: streams.first { $0.type == "Video" }?.displayTitle,
                size: source.size, subtitles: subtitles
            )
        }
    }

    private enum CodingKeys: String, CodingKey { case id = "Id", mediaSources = "MediaSources" }
}

/// `PlaybackStartInfo`, `PlaybackProgressInfo` and `PlaybackStopInfo`, which share these fields.
private struct PlaybackInfo: Encodable {
    let itemID: String
    let mediaSourceID: String
    let playSessionID: String
    let positionTicks: Int64
    let isPaused: Bool
    let canSeek = true
    let playMethod = "DirectPlay"

    init(_ report: JellyfinPlaybackReport) {
        itemID = report.item.rawValue
        mediaSourceID = report.file.rawValue
        playSessionID = report.playSession
        // A tick is 100 ns.
        positionTicks = report.position.components.seconds * 10_000_000 + report.position.components.attoseconds / 100_000_000_000
        isPaused = report.isPaused
    }

    private enum CodingKeys: String, CodingKey {
        case itemID = "ItemId", mediaSourceID = "MediaSourceId", playSessionID = "PlaySessionId", positionTicks = "PositionTicks"
        case isPaused = "IsPaused", canSeek = "CanSeek", playMethod = "PlayMethod"
    }
}
