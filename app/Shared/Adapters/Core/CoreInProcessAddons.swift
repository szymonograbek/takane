import Foundation

// Add-ons the app answers itself, such as the user's media sources: how core lists them
// (`SourceAddonDescriptor`), reaches them (`CoreInProcessAddons`) and plays what they offer
// (`CorePlaybackLinks`). Core holds only their placeholder URLs, so its state, its storage and
// the logs of what it does carry no credential.

/// A URL under `<add-on id>.source.invalid`, the reserved domain of the add-ons the app answers
/// itself (core/src/sources.rs). Nothing on the network answers it.
struct InProcessURL: Hashable, Sendable {
    fileprivate static let domain = "source.invalid"

    /// Can name a file on the user's server.
    let url: Redacted<URL>
    /// The add-on it belongs to: the host's first label, `SourceAddonDescriptor.id`.
    let addonID: String

    init?(_ url: URL) {
        guard url.scheme == "https", let host = url.host(), host.hasSuffix(".\(Self.domain)") else { return nil }
        self.url = Redacted(url)
        addonID = String(host.prefix { $0 != "." })
    }
}

/// An HTTP answer, as the add-on's server would give it.
struct CoreFetchReply: Sendable {
    let status: UInt16
    let body: Data
}

/// Add-ons answered in the app. Core's requests for an `InProcessURL` come here, never to the network.
protocol CoreInProcessAddons: Sendable {
    func respond(to url: InProcessURL) async -> CoreFetchReply
}

/// Turns the placeholder stream and subtitle URLs that in-process add-ons give core into what the
/// player loads.
protocol CorePlaybackLinks: Sendable {
    /// Nil when the placeholder names nothing the add-on still has.
    func playbackSource(for placeholder: InProcessURL) -> PlaybackSource?
}

/// Hears what the player does with in-process add-ons' streams, so an add-on can tell its server
/// what was watched.
protocol CorePlaybackReports: Sendable {
    func playback(_ event: InProcessPlayback)
}

/// What the player did with an in-process add-on's stream, in the order it happened.
enum InProcessPlayback: Equatable, Sendable {
    /// The stream with this placeholder began, after whatever played before.
    case began(InProcessURL)
    /// The stream playing is at this position, playing through or after a seek.
    case position(Duration)
    case paused(Bool)
    /// The stream ended or was closed, or one from elsewhere began.
    case stopped
}

extension CorePlaybackLinks {
    /// What the player loads for a URL core holds: the URL itself with `headers`, or the file an
    /// in-process add-on's placeholder stands for, nil when it stands for none.
    func playbackSource(for url: URL, headers: [String: String]) -> PlaybackSource? {
        guard let placeholder = InProcessURL(url) else { return PlaybackSource(url: Redacted(url), headers: headers) }
        return playbackSource(for: placeholder)
    }

    func playability(of stream: Stream) -> Playability {
        switch stream.source {
        case .url(let url):
            playbackSource(for: url, headers: stream.requestHeaders).map(Playability.playable) ?? .unsupported(kind: "UnknownSourceLink")
        case .unsupported(let kind):
            .unsupported(kind: kind)
        }
    }
}

/// A source add-on as `setSources` lists it, in core's `Descriptor` shape: transport URL
/// `https://<id>.source.invalid/manifest.json`, and ids that are IMDb's (`tt…`) or its own local
/// ones (`takane-<id>-…`), whose metadata only it gives. The bridge refuses any other.
struct SourceAddonDescriptor: Encodable, Equatable, Sendable {
    struct Catalog: Encodable, Equatable, Sendable {
        /// core's `ExtraProp`.
        struct Extra: Encodable, Equatable, Sendable {
            let name: String
        }

        let type: String
        let id: String
        let name: String
        let extra: [Extra]

        /// A searchable catalog also answers `search=…` with its matching titles, so Search lists it.
        init(type: String, id: String, name: String, searchable: Bool = false) {
            self.type = type
            self.id = id
            self.name = name
            extra = searchable ? [Extra(name: "search")] : []
        }
    }

    /// The beginning of every local id, as in core/src/sources.rs.
    static let localIDPrefix = "takane-"

    /// Lowercase letters and digits: a host name label that a local id can hold.
    let id: String
    let transportURL: URL
    /// What this add-on's local ids start with.
    let localIDPrefix: String
    let name: String
    let catalogs: [Catalog]

    init?(id: String, name: String, catalogs: [Catalog]) {
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber) }),
              let url = URL(string: "https://\(id).\(InProcessURL.domain)/manifest.json")
        else { return nil }
        self.id = id
        transportURL = url
        localIDPrefix = "\(Self.localIDPrefix)\(id)-"
        self.name = name
        self.catalogs = catalogs
    }

    private enum CodingKeys: String, CodingKey { case transportUrl, manifest }

    private struct Manifest: Encodable {
        struct Resource: Encodable {
            let name: String
            let types: [String]
            let idPrefixes: [String]
        }

        let id: String
        let version = "1.0.0"
        let name: String
        let types = ["movie", "series"]
        let idPrefixes: [String]
        let resources: [ResourceEntry]
        let catalogs: [Catalog]
    }

    /// core's `ManifestResource`: a name, or a name with its own types and id prefixes.
    private enum ResourceEntry: Encodable {
        case all(String)
        case only(Manifest.Resource)

        func encode(to encoder: any Encoder) throws {
            switch self {
            case .all(let name): try name.encode(to: encoder)
            case .only(let resource): try resource.encode(to: encoder)
            }
        }
    }

    /// The manifest the add-on answers `manifest.json` with, and the one core lists it by.
    func encodedManifest() throws -> Data {
        try JSONEncoder().encode(manifest)
    }

    private var manifest: Manifest {
        Manifest(
            id: "app.takane.source.\(id)",
            name: name,
            idPrefixes: ["tt", localIDPrefix],
            // Cinemeta keeps the metadata of `tt` ids.
            resources: [
                .all("catalog"),
                .only(Manifest.Resource(name: "meta", types: ["movie", "series"], idPrefixes: [localIDPrefix])),
                .all("stream"),
                .all("subtitles"),
            ],
            catalogs: catalogs
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transportURL, forKey: .transportUrl)
        try container.encode(manifest, forKey: .manifest)
    }
}
