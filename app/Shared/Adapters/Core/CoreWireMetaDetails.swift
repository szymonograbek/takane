import Foundation

// The meta_details model's state, apart from `CoreWire.swift` to keep both files short.

struct MetaDetailsState: Decodable, Sendable {
    struct Selected: Decodable, Sendable {
        let metaPath: ResourcePath
        let streamPath: ResourcePath?
    }

    /// core's `RatingInfo`.
    struct RatingInfo: Decodable, Sendable {
        /// "watched", "liked" or "loved", or nil when the viewer gave none.
        let status: String?
    }

    /// core's `MetaItem`: the preview fields plus the title's videos.
    struct MetaItem: Decodable, Sendable {
        let preview: MetaItemPreview
        let videos: [Video]

        private enum CodingKeys: String, CodingKey { case videos }

        init(from decoder: any Decoder) throws {
            preview = try MetaItemPreview(from: decoder)
            videos = try decoder.container(keyedBy: CodingKeys.self).decode([Video].self, forKey: .videos)
        }
    }

    struct Video: Decodable, Sendable {
        let id: String
        let title: String
        /// RFC 3339.
        let released: String?
        let overview: String?
        let thumbnail: String?
        let season: Int?
        let episode: Int?
        /// core's full video JSON, handed back when marking it watched.
        let raw: JSONValue

        private enum CodingKeys: String, CodingKey { case id, title, released, overview, thumbnail, season, episode }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            released = try container.decodeIfPresent(String.self, forKey: .released)
            overview = try container.decodeIfPresent(String.self, forKey: .overview)
            thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
            season = try container.decodeIfPresent(Int.self, forKey: .season)
            episode = try container.decodeIfPresent(Int.self, forKey: .episode)
            raw = try JSONValue(from: decoder)
        }
    }

    let selected: Selected?
    let metaItems: [ResourceLoadable<MetaItem>]
    /// Streams the first ready meta item embeds in the selected video, always ready, requested as
    /// the stream resource from the meta add-on.
    let metaStreams: [ResourceLoadable<[Stream]>]
    let streams: [ResourceLoadable<[Stream]>]
    /// The shown title's library item, also when the library does not hold it yet.
    let libraryItem: LibraryItem?
    /// Ids of the first ready meta item's videos the user has watched. The bridge adds it, since
    /// core leaves its watched bitfield out of the state.
    let watchedVideos: Set<String>
    /// The viewer's rating of the shown title. Nil when signed out or core does not rate the title.
    let ratingInfo: Loadable<RatingInfo>?

    /// The first ready meta item, which core's watched marks refer to, when the model holds `metaPath`.
    func metaItem(at metaPath: ResourcePath) -> MetaItem? {
        guard selected?.metaPath == metaPath else { return nil }
        return metaItems.lazy.compactMap { $0.content?.readyContent }.first
    }
}

extension MetaDetailsState.Video {
    /// The video as the app knows it, when its id is a `PlayableID`. `watched` holds the ids of the
    /// title's videos the viewer watched.
    func video(watched: Set<String>) -> Video? {
        PlayableID(id).map { playable in
            Video(
                playable: playable, name: Redacted(title), season: season, episode: episode,
                released: released.flatMap(Date.init(core:)), thumbnail: thumbnail.flatMap(URL.init(string:)),
                overview: overview.map(Redacted.init), isWatched: watched.contains(id)
            )
        }
    }
}

extension TitleRating {
    /// core's `Rating`. Its third status, "watched", is neither a like nor a love.
    init?(core name: String) {
        switch name {
        case "liked": self = .liked
        case "loved": self = .loved
        default: return nil
        }
    }

    var coreName: String {
        switch self {
        case .liked: "liked"
        case .loved: "loved"
        }
    }
}
