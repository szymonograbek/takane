#if DEBUG
import Foundation

/// A source add-on answered from memory over the dev WebDAV server (`scripts/dev-sources.sh up`),
/// to check core's in-process add-on and playback-link hooks before real sources exist. Debug
/// builds only: it holds the dev server's password.
///
/// `STREMIO_FIXTURE_SOURCE=1` (see `LaunchOptions`) lists it. Home gains a Fixture row with Sintel,
/// matched by its IMDb id so its details are Cinemeta's, and Beach Day, a local id whose details
/// are this add-on's. Each has a stream, and Sintel has its sidecar subtitles. Core sees only
/// placeholder URLs; `playbackSource(for:)` turns them into the server's files with Basic auth.
struct FixtureSource: CoreInProcessAddons, CorePlaybackLinks, CorePlaybackReports {
    private struct Title {
        let id: String
        let name: String
        let poster: String?
        /// The file's path on the WebDAV server.
        let file: String
        let subtitles: String?
    }

    private static let titles = [
        Title(
            id: "tt1727587", name: "Sintel", poster: "https://images.metahub.space/poster/medium/tt1727587/img",
            file: "/Movies/Sintel (2010) [imdbid-tt1727587]/Sintel (2010).mkv",
            subtitles: "/Movies/Sintel (2010) [imdbid-tt1727587]/Sintel (2010).en.srt"
        ),
        Title(id: "takane-fixture-beach", name: "Beach Day", poster: nil, file: "/Home Videos/Beach Day.mp4", subtitles: nil),
    ]

    let descriptor: SourceAddonDescriptor
    private let server: URL
    private let headers = ["Authorization": "Basic \(Data("takane:takane-dev".utf8).base64EncodedString())"]

    init?() {
        guard let descriptor = SourceAddonDescriptor(
            id: "fixture", name: "Fixture", catalogs: [SourceAddonDescriptor.Catalog(type: "movie", id: "fixture", name: "Fixture")]
        ), let server = URL(string: "http://localhost:8197") else { return nil }
        self.descriptor = descriptor
        self.server = server
    }

    func respond(to url: InProcessURL) async -> CoreFetchReply {
        // `/<resource>/<type>/<id>.json`, or `/<resource>/<type>/<id>/<extra>.json`.
        let path = Array(url.url.rawValue.pathComponents.dropFirst())
        let id = path.count > 2 ? path[2].replacingOccurrences(of: ".json", with: "") : ""
        let title = Self.titles.first { $0.id == id }
        do {
            switch path.first {
            case "manifest.json":
                return CoreFetchReply(status: 200, body: try descriptor.encodedManifest())
            case "catalog":
                return try Self.reply(["metas": Self.titles.map(Preview.init)])
            case "meta":
                guard let title, title.id.hasPrefix(descriptor.localIDPrefix) else { return CoreFetchReply(status: 404, body: Data()) }
                return try Self.reply(["meta": Meta(title)])
            case "stream":
                let streams = title.map { [StreamItem(url: placeholder("play", $0), title: $0.file.split(separator: "/").last.map(String.init))] }
                return try Self.reply(["streams": streams ?? []])
            case "subtitles":
                let subtitles = title.flatMap { $0.subtitles == nil ? nil : [SubtitleItem(id: "fixture-\($0.id)-en", url: placeholder("subtitle", $0))] }
                return try Self.reply(["subtitles": subtitles ?? []])
            default:
                return CoreFetchReply(status: 404, body: Data())
            }
        } catch {
            return CoreFetchReply(status: 500, body: Data())
        }
    }

    func playbackSource(for placeholder: InProcessURL) -> PlaybackSource? {
        let path = Array(placeholder.url.rawValue.pathComponents.dropFirst())
        guard path.count == 2, let title = Self.titles.first(where: { $0.id == path[1] }) else { return nil }
        let file: String? = switch path[0] {
        case "play": title.file
        case "subtitle": title.subtitles
        default: nil
        }
        return file.map { PlaybackSource(url: Redacted(server.appending(path: $0)), headers: headers) }
    }

    /// The dev WebDAV server keeps no watched state.
    func playback(_ event: InProcessPlayback) {}

    private func placeholder(_ kind: String, _ title: Title) -> String {
        descriptor.transportURL.deletingLastPathComponent().appending(path: "\(kind)/\(title.id)").absoluteString
    }

    private static func reply(_ body: some Encodable) throws -> CoreFetchReply {
        CoreFetchReply(status: 200, body: try JSONEncoder().encode(body))
    }

    private struct Preview: Encodable {
        let id: String
        let type = "movie"
        let name: String
        let poster: String?

        init(_ title: Title) {
            id = title.id
            name = title.name
            poster = title.poster
        }
    }

    private struct Meta: Encodable {
        let id: String
        let type = "movie"
        let name: String
        let description = "A day at the beach, from the dev WebDAV server's Home Videos."

        init(_ title: Title) {
            id = title.id
            name = title.name
        }
    }

    private struct StreamItem: Encodable {
        let url: String
        let name = "Fixture"
        let title: String?
    }

    private struct SubtitleItem: Encodable {
        let id: String
        let url: String
        let lang = "eng"
    }
}
#endif
