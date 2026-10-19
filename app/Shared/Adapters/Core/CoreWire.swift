import Foundation

// Decodable views of core model state (`sb_get_state`). Each type decodes only the fields
// the app reads; core's JSON carries more.

/// core's `Loadable`: `{"type": "Loading"}`, `{"type": "Ready", "content": …}`, `{"type": "Err", "content": …}`.
enum Loadable<Content: Decodable & Sendable>: Decodable, Sendable {
    case loading
    case ready(Content)
    case failed(JSONValue)

    private enum CodingKeys: String, CodingKey { case type, content }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "Loading": self = .loading
        case "Ready": self = .ready(try container.decode(Content.self, forKey: .content))
        default: self = .failed(try container.decodeIfPresent(JSONValue.self, forKey: .content) ?? .null)
        }
    }

    var readyContent: Content? {
        if case .ready(let content) = self { content } else { nil }
    }

    var isSettled: Bool {
        if case .loading = self { false } else { true }
    }
}

/// core's `ResourceLoadable`: one addon's response to one resource request.
struct ResourceLoadable<Content: Decodable & Sendable>: Decodable, Sendable {
    let request: ResourceRequest
    let content: Loadable<Content>?
}

// MARK: - ctx

struct CtxState: Decodable, Sendable {
    let profile: Profile
}

struct Profile: Decodable, Sendable {
    struct Auth: Decodable, Sendable {
        struct User: Decodable, Sendable { let email: String }
        let user: User
    }

    let auth: Auth?
    let addons: [Addon]
    /// core's `Settings`, kept whole so an update sends back every key it did not change.
    let settings: JSONValue
}

/// An installed or remote addon. `descriptor` is core's full JSON, sent back as-is on install.
struct Addon: Decodable, Sendable, Identifiable {
    struct Manifest: Decodable, Sendable {
        let id: String
        let name: String
        let version: String
        let catalogs: [Catalog]
    }

    /// core's `ManifestCatalog`.
    struct Catalog: Decodable, Sendable {
        let id: String
        let type: String
        let name: String?
        /// The extra properties the catalog accepts, such as `search` and `skip`.
        let extraNames: [String]

        private struct ExtraProp: Decodable { let name: String }
        private enum CodingKeys: String, CodingKey { case id, type, name, extra, extraSupported }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            type = try container.decode(String.self, forKey: .type)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            // core keeps the manifest's own form: `extra` objects, or the legacy `extraSupported` names.
            if let props = try container.decodeIfPresent([ExtraProp].self, forKey: .extra) {
                extraNames = props.map(\.name)
            } else {
                extraNames = try container.decodeIfPresent([String].self, forKey: .extraSupported) ?? []
            }
        }
    }

    struct Flags: Decodable, Sendable {
        /// One of Stremio's own add-ons, which every new profile starts with.
        let isOfficial: Bool
        /// Core refuses to uninstall a protected add-on.
        let isProtected: Bool

        private enum CodingKeys: String, CodingKey {
            case isOfficial = "official"
            case isProtected = "protected"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isOfficial = try container.decodeIfPresent(Bool.self, forKey: .isOfficial) ?? false
            isProtected = try container.decodeIfPresent(Bool.self, forKey: .isProtected) ?? false
        }
    }

    let manifest: Manifest
    let transportUrl: URL
    let flags: Flags?
    let descriptor: JSONValue

    var id: URL { transportUrl }

    private enum CodingKeys: String, CodingKey { case manifest, transportUrl, flags }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifest = try container.decode(Manifest.self, forKey: .manifest)
        transportUrl = try container.decode(URL.self, forKey: .transportUrl)
        flags = try container.decodeIfPresent(Flags.self, forKey: .flags)
        descriptor = try JSONValue(from: decoder)
    }
}

// MARK: - addon_details

struct AddonDetailsState: Decodable, Sendable {
    /// core's `DescriptorLoadable`, which (unlike most core types) serializes in snake_case.
    struct RemoteAddon: Decodable, Sendable {
        let transportUrl: URL
        let content: Loadable<Addon>

        private enum CodingKeys: String, CodingKey {
            case transportUrl = "transport_url"
            case content
        }
    }

    let remoteAddon: RemoteAddon?
}

// MARK: - board, search

/// core's `CatalogsWithExtra`.
struct CatalogsState: Decodable, Sendable {
    /// Nil until the model is loaded.
    let selected: CatalogsSelection?
    /// One entry per catalog the selection matched, each a list of pages. A page with no `content`
    /// is listed but not requested yet.
    let catalogs: [[ResourceLoadable<[MetaItemPreview]>]]
}

/// core's `MetaItemPreview`. Core folds an add-on's `genres` and `imdbRating` into `links`.
struct MetaItemPreview: Decodable, Sendable {
    struct Link: Decodable, Sendable {
        let name: String
        let category: String
    }

    let id: String
    let type: String
    let name: String
    // URLs are decoded as text so one malformed URL drops that image instead of failing the state.
    let poster: String?
    let background: String?
    let logo: String?
    let description: String?
    let releaseInfo: String?
    let runtime: String?
    /// `poster`, `landscape` or `square`.
    let posterShape: String
    let links: [Link]
}

// MARK: - meta_details

struct MetaDetailsState: Decodable, Sendable {
    struct Selected: Decodable, Sendable {
        let metaPath: ResourcePath
        let streamPath: ResourcePath?
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

    /// The first ready meta item, which core's watched marks refer to, when the model holds `metaPath`.
    func metaItem(at metaPath: ResourcePath) -> MetaItem? {
        guard selected?.metaPath == metaPath else { return nil }
        return metaItems.lazy.compactMap { $0.content?.readyContent }.first
    }
}

/// An addon stream. Only `.url` sources are playable without a streaming server.
struct Stream: Decodable, Sendable {
    enum Source: Sendable, Equatable {
        case url(URL)
        /// Torrent, archive, YouTube, external link and similar; `kind` names it for logs and UI.
        case unsupported(kind: String)
    }

    let source: Source
    let name: String?
    let description: String?
    let filename: String?
    /// Headers the stream requires on every HTTP request (`behaviorHints.proxyHeaders.request`).
    let requestHeaders: [String: String]
    /// core's full stream JSON, handed back when loading the player model.
    let raw: JSONValue

    private enum CodingKeys: String, CodingKey {
        case url, ytId, infoHash, externalUrl, playerFrameUrl, nzbUrl
        case rarUrls, zipUrls, zip7Urls = "7zipUrls", tgzUrls, tarUrls
        case name, description, title, behaviorHints
    }

    private struct BehaviorHints: Decodable {
        struct ProxyHeaders: Decodable { let request: [String: String]? }
        let proxyHeaders: ProxyHeaders?
        let filename: String?
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Decoded as text so one malformed URL marks one stream unsupported instead of failing the list.
        if let text = try container.decodeIfPresent(String.self, forKey: .url) {
            source = URL(string: text).map(Source.url) ?? .unsupported(kind: "InvalidUrl")
        } else {
            let kinds: [(CodingKeys, String)] = [
                (.ytId, "YouTube"), (.infoHash, "Torrent"), (.externalUrl, "External"),
                (.playerFrameUrl, "PlayerFrame"), (.nzbUrl, "Nzb"), (.rarUrls, "Rar"), (.zipUrls, "Zip"),
                (.zip7Urls, "7zip"), (.tgzUrls, "Tgz"), (.tarUrls, "Tar"),
            ]
            source = .unsupported(kind: kinds.first { container.contains($0.0) }?.1 ?? "Unknown")
        }
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
            ?? container.decodeIfPresent(String.self, forKey: .title)
        let hints = try container.decodeIfPresent(BehaviorHints.self, forKey: .behaviorHints)
        filename = hints?.filename
        requestHeaders = hints?.proxyHeaders?.request ?? [:]
        raw = try JSONValue(from: decoder)
    }
}

// MARK: - player

struct PlayerState: Decodable, Sendable {
    /// What `CoreAction.Load.player` loaded, as core echoes it back.
    struct Selected: Decodable, Sendable {
        let stream: Stream
        let subtitlesPath: ResourcePath?
    }

    let selected: Selected?
    let subtitles: [ResourceLoadable<[Subtitles]>]
}

/// core's `Subtitles`, one file an add-on offers.
struct Subtitles: Decodable, Sendable {
    let id: String
    let lang: String
    /// Decoded as text so one malformed URL drops that file instead of the add-on's list.
    let url: String
    let label: String?
}

// MARK: - continue_watching_preview

struct ContinueWatchingState: Decodable, Sendable {
    /// Each item is a library item (flattened) plus a notification count the app ignores for now.
    let items: [LibraryItem]
}

// MARK: - library

struct LibraryItem: Decodable, Sendable {
    struct State: Decodable, Sendable {
        /// Milliseconds.
        let timeOffset: UInt64
        /// Milliseconds.
        let duration: UInt64
        /// The video watched last, such as `tt0944947:1:2`.
        let videoId: String?
        /// Counts each watch of a movie, or of any episode of a series; zero once marked unwatched.
        let timesWatched: UInt32

        private enum CodingKeys: String, CodingKey {
            case timeOffset, duration, timesWatched
            case videoId = "video_id"
        }
    }

    let id: String
    let name: String
    let type: String
    /// Decoded as text so one malformed URL drops the image instead of the item.
    let poster: String?
    let state: State

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, type, poster, state
    }
}

// MARK: - link

/// core's `Link<LinkAuthKey>`.
struct LinkState: Decodable, Sendable {
    struct Code: Decodable, Sendable {
        let code: String
        let link: String
    }

    struct AuthKey: Decodable, Sendable {
        let authKey: String
    }

    let code: Loadable<Code>?
    let data: Loadable<AuthKey>?
}
