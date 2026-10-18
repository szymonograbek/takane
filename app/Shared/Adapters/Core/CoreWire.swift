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
}

/// An installed or remote addon. `descriptor` is core's full JSON, sent back as-is on install.
struct Addon: Decodable, Sendable, Identifiable {
    struct Manifest: Decodable, Sendable {
        let id: String
        let name: String
        let version: String
    }

    let manifest: Manifest
    let transportUrl: URL
    let descriptor: JSONValue

    var id: URL { transportUrl }

    private enum CodingKeys: String, CodingKey { case manifest, transportUrl }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifest = try container.decode(Manifest.self, forKey: .manifest)
        transportUrl = try container.decode(URL.self, forKey: .transportUrl)
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

// MARK: - meta_details

struct MetaDetailsState: Decodable, Sendable {
    struct Selected: Decodable, Sendable {
        let streamPath: ResourcePath?
    }

    struct MetaItem: Decodable, Sendable {
        let id: String
        let type: String
        let name: String
    }

    let selected: Selected?
    let metaItems: [ResourceLoadable<MetaItem>]
    let streams: [ResourceLoadable<[Stream]>]
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
    }

    let id: String
    let name: String
    let state: State

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, state
    }
}
