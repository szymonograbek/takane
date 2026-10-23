import Foundation
import Testing

struct CoreStreamResultsTests {
    private static let cinemeta = "https://cinemeta.example/manifest.json"
    private static let other = "https://other-meta.example/manifest.json"
    private static let debrid = "https://debrid.example/manifest.json"

    private struct NoLinks: CorePlaybackLinks {
        func playbackSource(for placeholder: InProcessURL) -> PlaybackSource? { nil }
    }

    private static func request(_ base: String, _ resource: String) -> String {
        #"{"base": "\#(base)", "path": {"resource": "\#(resource)", "type": "movie", "id": "tt0111161", "extra": []}}"#
    }

    private static func metaRequestJSON(_ base: String) -> JSONValue {
        .object([
            "base": .string(base),
            "path": .object([
                "resource": .string("meta"), "type": .string("movie"), "id": .string("tt0111161"), "extra": .array([]),
            ]),
        ])
    }

    /// core's `meta_details` state for the Shawshank Redemption with one ready stream from `debrid`.
    private static func details(metaItems: String, metaStreams: String = "") throws -> MetaDetailsState {
        let json = """
        {
            "selected": {
                "metaPath": {"resource": "meta", "type": "movie", "id": "tt0111161", "extra": []},
                "streamPath": {"resource": "stream", "type": "movie", "id": "tt0111161", "extra": []}
            },
            "metaItems": [\(metaItems)],
            "metaStreams": [\(metaStreams)],
            "streams": [{
                "request": \(request(debrid, "stream")),
                "content": {"type": "Ready", "content": [{"url": "https://cdn.example/movie.mkv", "name": "1080p"}]}
            }],
            "watchedVideos": []
        }
        """
        return try JSONDecoder().decode(MetaDetailsState.self, from: Data(json.utf8))
    }

    private static func metaItem(_ base: String, content: String) -> String {
        #"{"request": \#(request(base, "meta")), "content": \#(content)}"#
    }

    /// The `metaRequest` each candidate's player selection carries, in list order.
    private static func metaRequests(in results: StreamResults) -> [JSONValue?] {
        results.sources.flatMap { $0.candidates.value ?? [] }.map { candidate in
            guard case .object(let selection) = candidate.tracking.payload.rawValue else { return nil }
            return selection["metaRequest"]
        }
    }

    @Test func streamPickedWhileMetadataLoadsCarriesTheMetaRequest() throws {
        let details = try Self.details(metaItems: Self.metaItem(Self.cinemeta, content: #"{"type": "Loading"}"#))
        let results = CoreStreamResults(links: NoLinks()).results(for: Fixture.movie, from: details, addonNames: [:])
        #expect(Self.metaRequests(in: results) == [Self.metaRequestJSON(Self.cinemeta)])
        #expect(!results.isComplete)
    }

    @Test func metaRequestPrefersTheAddonThatAnswered() throws {
        let details = try Self.details(metaItems: [
            Self.metaItem(Self.cinemeta, content: #"{"type": "Err", "content": {"type": "UnexpectedResponse"}}"#),
            Self.metaItem(Self.other, content: Self.readyMeta(videos: "[]")),
        ].joined(separator: ","))
        let results = CoreStreamResults(links: NoLinks()).results(for: Fixture.movie, from: details, addonNames: [:])
        #expect(Self.metaRequests(in: results) == [Self.metaRequestJSON(Self.other)])
        #expect(results.isComplete)
    }

    @Test func everyMetaAddonFailingStillCarriesAMetaRequest() throws {
        let details = try Self.details(
            metaItems: Self.metaItem(Self.cinemeta, content: #"{"type": "Err", "content": {"type": "UnexpectedResponse"}}"#)
        )
        let results = CoreStreamResults(links: NoLinks()).results(for: Fixture.movie, from: details, addonNames: [:])
        #expect(Self.metaRequests(in: results) == [Self.metaRequestJSON(Self.cinemeta)])
    }

    /// Each candidate's id and the `streamRequest` its player selection carries, in list order.
    private static func streamRequests(in results: StreamResults) -> [String] {
        results.sources.flatMap { $0.candidates.value ?? [] }.map { candidate in
            guard case .object(let selection) = candidate.tracking.payload.rawValue,
                  case .object(let request)? = selection["streamRequest"],
                  case .string(let base)? = request["base"],
                  case .object(let path)? = request["path"],
                  case .string(let resource)? = path["resource"] else { return "\(candidate.id.index) none" }
            return "\(candidate.id.addon.url.rawValue.host() ?? "?") \(candidate.id.index) \(resource) from \(base)"
        }
    }

    private static func embeddedStreams(_ base: String) -> String {
        """
        {"request": \(request(base, "stream")),
         "content": {"type": "Ready", "content": [{"url": "https://cdn.example/embedded.mkv", "name": "Embedded"}]}}
        """
    }

    @Test func embeddedStreamsAreASourceOfTheirAddon() throws {
        let details = try Self.details(
            metaItems: Self.metaItem(Self.other, content: Self.readyMeta(videos: "[]")),
            metaStreams: Self.embeddedStreams(Self.other)
        )
        let names = [URL(string: Self.other).require(): Redacted("Other Meta"), URL(string: Self.debrid).require(): Redacted("Debrid")]
        let results = CoreStreamResults(links: NoLinks()).results(for: Fixture.movie, from: details, addonNames: names)
        #expect(results.sources.map(\.addonName.rawValue) == ["Other Meta", "Debrid"])
        #expect(Self.streamRequests(in: results) == [
            "other-meta.example 0 stream from \(Self.other)",
            "debrid.example 0 stream from \(Self.debrid)",
        ])
        #expect(Self.metaRequests(in: results) == [Self.metaRequestJSON(Self.other), Self.metaRequestJSON(Self.other)])
        #expect(results.isComplete)
    }

    @Test func embeddedAndRequestedStreamsOfOneAddonShareItsSource() throws {
        let details = try Self.details(
            metaItems: Self.metaItem(Self.debrid, content: Self.readyMeta(videos: "[]")),
            metaStreams: Self.embeddedStreams(Self.debrid)
        )
        let results = CoreStreamResults(links: NoLinks()).results(for: Fixture.movie, from: details, addonNames: [:])
        #expect(results.sources.map(\.addonName.rawValue) == ["debrid.example"])
        #expect(results.sources.first?.candidates.value?.map(\.name?.rawValue) == ["Embedded", "1080p"])
        #expect(Self.streamRequests(in: results) == [
            "debrid.example 0 stream from \(Self.debrid)",
            "debrid.example 1 stream from \(Self.debrid)",
        ])
    }

    private static func readyMeta(videos: String) -> String {
        """
        {"type": "Ready", "content": {
            "id": "tt0111161", "type": "movie", "name": "The Shawshank Redemption", "posterShape": "poster",
            "links": [], "videos": \(videos)
        }}
        """
    }
}
