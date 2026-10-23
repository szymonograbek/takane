import Foundation
import Testing

struct CoreInProcessAddonsTests {
    private static let sintel = PlayableID("tt1727587").require()
    private static let source = "https://ab12cd34.source.invalid/manifest.json"
    private static let placeholder = "https://ab12cd34.source.invalid/play/sintel"
    private static let nas = PlaybackSource(
        url: Redacted(URL(string: "http://nas.local:8197/Movies/Sintel.mkv").require()),
        headers: ["Authorization": "Basic dGFrYW5lOnNlY3JldA=="]
    )

    private struct Links: CorePlaybackLinks {
        let files: [String: PlaybackSource]

        func playbackSource(for placeholder: InProcessURL) -> PlaybackSource? {
            files[placeholder.url.rawValue.absoluteString]
        }
    }

    private static let links = Links(files: [placeholder: nas])

    @Test func onlySourceAddonURLsAreAnsweredInProcess() throws {
        let inProcess = try [
            "https://ab12cd34.source.invalid/manifest.json",
            "https://ab12cd34.source.invalid/stream/movie/tt1727587.json",
        ].map { InProcessURL(try #require(URL(string: $0))) != nil }
        let network = try [
            "https://open-movies.invalid/manifest.json",
            "https://source.invalid.example.com/manifest.json",
            "http://ab12cd34.source.invalid/manifest.json",
            "https://v3-cinemeta.strem.io/manifest.json",
        ].map { InProcessURL(try #require(URL(string: $0))) != nil }
        #expect(inProcess == [true, true])
        #expect(network == [false, false, false, false])
    }

    /// core's `meta_details` state for Sintel with one stream from the source add-on and one from Open Movies.
    private static func details(sourceStream: String) throws -> MetaDetailsState {
        func request(_ base: String) -> String {
            #"{"base": "\#(base)", "path": {"resource": "stream", "type": "movie", "id": "tt1727587", "extra": []}}"#
        }
        let json = """
        {
            "selected": {
                "metaPath": {"resource": "meta", "type": "movie", "id": "tt1727587", "extra": []},
                "streamPath": {"resource": "stream", "type": "movie", "id": "tt1727587", "extra": []}
            },
            "metaItems": [],
            "metaStreams": [],
            "streams": [
                {"request": \(request(source)),
                 "content": {"type": "Ready", "content": [{"url": "\(sourceStream)", "name": "Home"}]}},
                {"request": \(request("https://open-movies.invalid/manifest.json")),
                 "content": {"type": "Ready", "content": [{"url": "https://download.blender.org/Sintel.mkv", "name": "Open Movies"}]}}
            ],
            "watchedVideos": []
        }
        """
        return try JSONDecoder().decode(MetaDetailsState.self, from: Data(json.utf8))
    }

    private static func candidates(_ details: MetaDetailsState) -> [StreamCandidate] {
        CoreStreamResults(links: links).results(for: Self.sintel, from: details, addonNames: [:])
            .sources.flatMap { $0.candidates.value ?? [] }
    }

    @Test func aPlaceholderStreamPlaysTheFileItStandsForWhileCoreKeepsThePlaceholder() throws {
        let candidates = Self.candidates(try Self.details(sourceStream: Self.placeholder))

        #expect(candidates.map(\.playability) == [
            .playable(Self.nas),
            .playable(PlaybackSource(url: Redacted(URL(string: "https://download.blender.org/Sintel.mkv").require()), headers: [:])),
        ])
        guard case .object(let selection) = candidates.first?.tracking.payload.rawValue,
              case .object(let stream)? = selection["stream"] else {
            Issue.record("no stream in the player selection")
            return
        }
        #expect(stream["url"] == .string(Self.placeholder))
    }

    @Test func aPlaceholderStandingForNothingIsUnplayable() throws {
        let candidates = Self.candidates(try Self.details(sourceStream: "https://ab12cd34.source.invalid/play/removed"))

        #expect(candidates.first?.playability == .unsupported(kind: "UnknownSourceLink"))
    }

    /// core's player state with the placeholder stream selected for Sintel.
    private static func player() throws -> PlayerState {
        try JSONDecoder().decode(PlayerState.self, from: Data("""
        {
            "selected": {
                "stream": {"url": "\(placeholder)", "name": "Home"},
                "streamRequest": null,
                "metaRequest": null,
                "subtitlesPath": {"resource": "subtitles", "type": "movie", "id": "tt1727587", "extra": []}
            },
            "subtitles": [],
            "metaItem": null,
            "nextVideo": null,
            "nextStreams": null,
            "nextStream": null,
            "streamState": null,
            "watchedVideos": []
        }
        """.utf8))
    }

    @Test func corePlaysTheCandidateWhoseFileItsPlaceholderStandsFor() throws {
        let player = try Self.player()
        let candidate = Fixture.candidate(.playable(Self.nas), item: Self.sintel)

        #expect(player.plays(candidate, from: Self.nas, links: Self.links))
        #expect(!player.plays(candidate, from: Self.nas, links: Links(files: [:])))
    }

    @Test func sourcesEncodeTheShapeTheBridgeParses() throws {
        let descriptor = try #require(SourceAddonDescriptor(
            id: "ab12cd34", name: "Home Jellyfin",
            catalogs: [SourceAddonDescriptor.Catalog(type: "movie", id: "movies", name: "Movies", extra: [.search, .skip])]
        ))
        let encoded = try JSONEncoder().encode(DispatchRequest.bridge(.setSources([descriptor])))

        // What `set_sources` in core/src/lib.rs builds for a valid source add-on.
        let expected = """
        {"setSources": {"descriptors": [{
            "transportUrl": "https://ab12cd34.source.invalid/manifest.json",
            "manifest": {
                "id": "app.takane.source.ab12cd34", "version": "1.0.0", "name": "Home Jellyfin",
                "types": ["movie", "series"], "idPrefixes": ["tt", "takane-ab12cd34-"],
                "resources": [
                    "catalog",
                    {"name": "meta", "types": ["movie", "series"], "idPrefixes": ["takane-ab12cd34-"]},
                    "stream",
                    "subtitles"
                ],
                "catalogs": [{"type": "movie", "id": "movies", "name": "Movies", "extra": [{"name": "search"}, {"name": "skip"}]}]
            }
        }]}}
        """
        #expect(try JSONDecoder().decode(JSONValue.self, from: encoded) == JSONDecoder().decode(JSONValue.self, from: Data(expected.utf8)))
    }

    @Test func aSourceIdThatCannotBeAHostLabelIsRefused() {
        let refused = ["", "AB12", "ab.12", "ab-12", "ab 12"].map { SourceAddonDescriptor(id: $0, name: "Home", catalogs: []) == nil }
        #expect(refused == [true, true, true, true, true])
    }
}
