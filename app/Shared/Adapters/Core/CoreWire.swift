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

extension JSONValue {
    /// core's error for an add-on that answered with an empty list.
    static let emptyContent = JSONValue.object(["type": .string("EmptyContent")])
}

extension PosterShape {
    /// core's `posterShape`. Like core, it reads anything else as a poster.
    init(core name: String) {
        self = switch name {
        case "landscape": .landscape
        case "square": .square
        default: .poster
        }
    }

    var coreName: String {
        switch self {
        case .poster: "poster"
        case .landscape: "landscape"
        case .square: "square"
        }
    }
}

extension Date {
    /// core's RFC 3339 times: whole seconds without a fraction, other times with one.
    init?(core text: String) {
        guard let date = (try? Date(text, strategy: .iso8601))
            ?? (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        else { return nil }
        self = date
    }
}

// MARK: - ctx

struct CtxState: Decodable, Sendable {
    let profile: Profile
    /// Queries most recent first. The bridge adds it, since core leaves its search history out of the state.
    let searchHistory: [String]
    /// Transport URLs of the add-ons switched off on this device. The bridge adds it, since core does not know about it.
    let disabledAddons: Set<URL>
    /// The user's sources, add-ons the app answers itself. The bridge adds them; core never holds them in `ctx`.
    let sourceAddons: [Addon]

    /// The add-ons every model but `ctx` asks, in their order: the installed ones this device uses,
    /// then the sources.
    var answeringAddons: [Addon] {
        profile.addons.filter { !disabledAddons.contains($0.transportUrl) } + sourceAddons
    }
}

struct Profile: Decodable, Sendable {
    struct Auth: Decodable, Sendable {
        let user: User
    }

    struct User: Decodable, Sendable {
        let id: Redacted<String>
        let email: Redacted<String>
        /// RFC 3339. When Stremio Premium ends, nil for an account that never had it.
        let premiumExpire: String?
        let trakt: Trakt?

        private enum CodingKeys: String, CodingKey {
            case id = "_id"
            case email
            case premiumExpire = "premium_expire"
            case trakt
        }
    }

    let auth: Auth?
    let addons: [Addon]
    /// core's `Settings`, kept whole so an update sends back every key it did not change.
    let settings: JSONValue

    /// Whether the account's Stremio Premium runs past now, the check core makes before asking for
    /// Stremio's skip times.
    var hasPremium: Bool {
        guard let end = auth?.user.premiumExpire.flatMap(Date.init(core:)) else { return false }
        return end > .now
    }
}

/// An installed or remote addon. `descriptor` is core's full JSON, sent back as-is on install.
struct Addon: Decodable, Sendable, Identifiable {
    struct Manifest: Decodable, Sendable {
        /// Both name the add-on, which release logs keep private.
        let id: Redacted<String>
        let name: Redacted<String>
        let version: String
        let catalogs: [Catalog]
    }

    /// core's `ManifestCatalog`.
    struct Catalog: Decodable, Sendable {
        let id: String
        let type: String
        let name: String?
        let extra: [ExtraProp]

        var extraNames: [String] { extra.map(\.name) }

        private enum CodingKeys: String, CodingKey { case id, type, name, extra, extraSupported, extraRequired }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            type = try container.decode(String.self, forKey: .type)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            // core keeps the manifest's own form: `extra` objects, or the legacy `extraSupported` names.
            if let extra = try container.decodeIfPresent([ExtraProp].self, forKey: .extra) {
                self.extra = extra
            } else {
                let required = try container.decodeIfPresent([String].self, forKey: .extraRequired) ?? []
                extra = try (container.decodeIfPresent([String].self, forKey: .extraSupported) ?? []).map { name in
                    ExtraProp(name: name, isRequired: required.contains(name), options: [])
                }
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

/// core's `ExtraProp`: an extra property a catalog accepts, such as `search`, `skip` or `genre`.
struct ExtraProp: Decodable, Sendable {
    let name: String
    let isRequired: Bool
    /// The values the catalog offers, such as its genres.
    let options: [String]
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

// MARK: - board, search, discover

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

/// core's `CatalogWithFilters`.
struct CatalogWithFiltersState: Decodable, Sendable {
    struct Selected: Decodable, Sendable {
        let request: ResourceRequest
    }

    /// Nil until the model is loaded.
    let selected: Selected?
    let catalog: [ResourceLoadable<[MetaItemPreview]>]
}

// MARK: - meta_details

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

// MARK: - link

/// core's `Link<LinkAuthKey>`.
struct LinkState: Decodable, Sendable {
    struct Code: Decodable, Sendable {
        let code: String
        let link: String
    }

    struct AuthKey: Decodable, Sendable {
        let authKey: Redacted<String>
    }

    let code: Loadable<Code>?
    let data: Loadable<AuthKey>?
}
