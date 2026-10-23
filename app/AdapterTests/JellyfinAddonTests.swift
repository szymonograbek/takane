import Foundation
import Synchronization
import Testing

/// A Jellyfin source's add-on, answering core from the dev server's recorded answers
/// (`app/AdapterTests/Jellyfin`, recorded with curl from `scripts/dev-sources.sh up`).
struct JellyfinAddonTests {
    private static let source = MediaSource(
        id: SourceID("abcd2345").require(), kind: .jellyfin, name: Redacted("Living Room"),
        endpoint: SourceEndpoint("http://jellyfin.local:8096").require(), username: SourceUsername("takane").require()
    )
    private static let session = JellyfinSession(userID: "u1", token: "0123456789abcdef0123456789abcdef")
    private static let root = "https://abcd2345.source.invalid"
    private static let local = "takane-abcd2345-"

    private static let sintel = "9952106a602633409354098d0e941df4"
    private static let pioneerOneS01E02 = "4bd88543bcfccf5104257962ade069eb"
    private static let pioneerOne = "041a7293b9e76a36eb168fdc578d8e51"
    private static let beachDay = "0ae549595ae7368e7ee4c03bfe70839c"
    private static let libraries = [
        "f137a2dd21bbc1b99aa5c0f6bf02a805": "jellyfin-items-movies",
        "a656b907eb3a73532e40e44b968d0225": "jellyfin-items-shows",
        "f4415c72cc16920fce19d78d636a3ce7": "jellyfin-items-home-videos",
    ]

    /// The dev server, its listings changed by `edit` (fixture name, body) when given.
    private static func server(
        edit: @escaping @Sendable (String, String) -> String = { $1 }
    ) -> @Sendable (URLRequest) -> HTTPStub.Response {
        { request in
            let path = request.url?.path() ?? ""
            let fixture: String? = switch path {
            case "/Users/u1/Views": "jellyfin-views"
            case "/Items" where request.query("Ids") != nil: "jellyfin-files-sintel-pioneer-one-s01e02"
            case "/Items": request.query("ParentId").flatMap { libraries[$0] }
            default: nil
            }
            guard let fixture else { return HTTPStub.Response(status: path.hasPrefix("/Sessions") ? 204 : 404, body: Data()) }
            return .json(edit(fixture, recorded(fixture)))
        }
    }

    private static func recorded(_ name: String) -> String {
        let url = Bundle(for: BundleMarker.self).url(forResource: name, withExtension: "json").require()
        return (try? String(contentsOf: url, encoding: .utf8)).require()
    }

    private static func addon(
        _ stub: HTTPStub, lifetime: Duration = JellyfinAddon.indexLifetime, catalogsChanged: @escaping @Sendable () -> Void = {}
    ) -> JellyfinAddon {
        JellyfinAddon(
            source: source, session: session, client: JellyfinClient(session: stub.session, version: "1.4.0"),
            lifetime: lifetime, catalogsChanged: catalogsChanged
        )
    }

    private static func url(_ path: String) -> InProcessURL {
        InProcessURL(URL(string: root + path).require()).require()
    }

    private static func json(_ addon: JellyfinAddon, _ path: String) async throws -> [String: Any] {
        let reply = await addon.respond(to: url(path))
        try #require(reply.status == 200, "\(path) answered \(reply.status)")
        return try #require(try JSONSerialization.jsonObject(with: reply.body) as? [String: Any])
    }

    private static func list(_ object: [String: Any], _ key: String) throws -> [[String: Any]] {
        try #require(object[key] as? [[String: Any]])
    }

    @Test func eachVideoLibraryIsASearchableCatalogOnceRead() async throws {
        let stub = HTTPStub(Self.server())
        let changes = Mutex(0)
        let addon = Self.addon(stub) { changes.withLock { $0 += 1 } }
        #expect(addon.descriptor?.catalogs == [])

        _ = try await Self.json(addon, "/catalog/movie/f137a2dd21bbc1b99aa5c0f6bf02a805.json")

        #expect(addon.descriptor?.catalogs == [
            SourceAddonDescriptor.Catalog(type: "movie", id: "f4415c72cc16920fce19d78d636a3ce7", name: "Home Videos", searchable: true),
            SourceAddonDescriptor.Catalog(type: "movie", id: "f137a2dd21bbc1b99aa5c0f6bf02a805", name: "Movies", searchable: true),
            SourceAddonDescriptor.Catalog(type: "series", id: "a656b907eb3a73532e40e44b968d0225", name: "Shows", searchable: true),
        ])
        #expect(changes.withLock { $0 } == 1)
        let manifest = try await Self.json(addon, "/manifest.json")
        let catalogs = try Self.list(manifest, "catalogs")
        #expect(catalogs.map { $0["name"] as? String } == ["Home Videos", "Movies", "Shows"])
        #expect(catalogs.allSatisfy { ($0["extra"] as? [[String: String]]) == [["name": "search"]] })
    }

    @Test func matchedTitlesUseTheirIMDbIdAndOthersALocalOne() async throws {
        let addon = Self.addon(HTTPStub(Self.server()))

        let movies = try Self.list(try await Self.json(addon, "/catalog/movie/f137a2dd21bbc1b99aa5c0f6bf02a805.json"), "metas")
        let shows = try Self.list(try await Self.json(addon, "/catalog/series/a656b907eb3a73532e40e44b968d0225.json"), "metas")
        let videos = try Self.list(try await Self.json(addon, "/catalog/movie/f4415c72cc16920fce19d78d636a3ce7.json"), "metas")

        #expect(Set(movies.compactMap { $0["id"] as? String }) == ["tt1727587", "tt1254207", "tt2285752", "tt0807840"])
        #expect(movies.allSatisfy { $0["type"] as? String == "movie" })
        let sintel = try #require(movies.first { $0["id"] as? String == "tt1727587" })
        #expect(sintel["poster"] as? String == "https://images.metahub.space/poster/medium/tt1727587/img")
        #expect(shows.map { $0["id"] as? String } == ["tt1748166"])
        #expect(shows.map { $0["type"] as? String } == ["series"])
        let beachDay = try #require(videos.first)
        #expect(beachDay["id"] as? String == Self.local + Self.beachDay)
        #expect(beachDay["name"] as? String == "Beach Day")
        #expect(beachDay["posterShape"] as? String == "landscape")
        let poster = try #require((beachDay["poster"] as? String).flatMap(URLComponents.init(string:)))
        #expect(poster.host == "jellyfin.local" && poster.path == "/Items/\(Self.beachDay)/Images/Primary")
    }

    @Test func searchKeepsTheTitlesWhoseNameHoldsTheQuery() async throws {
        let addon = Self.addon(HTTPStub(Self.server()))

        let movies = try Self.list(try await Self.json(addon, "/catalog/movie/f137a2dd21bbc1b99aa5c0f6bf02a805/search=SINTEL.json"), "metas")
        let twoWords = try Self.list(try await Self.json(addon, "/catalog/movie/f137a2dd21bbc1b99aa5c0f6bf02a805/search=buck%20bunny.json"), "metas")
        let shows = try Self.list(try await Self.json(addon, "/catalog/series/a656b907eb3a73532e40e44b968d0225/search=sintel.json"), "metas")

        #expect(movies.map { $0["id"] as? String } == ["tt1727587"])
        #expect(twoWords.map { $0["id"] as? String } == ["tt1254207"])
        #expect(shows.isEmpty)
    }

    @Test func onlyLocalTitlesHaveMetadataHere() async throws {
        let addon = Self.addon(HTTPStub(Self.server()))

        let meta = try #require(try await Self.json(addon, "/meta/movie/\(Self.local)\(Self.beachDay).json")["meta"] as? [String: Any])
        let cinemetas = await addon.respond(to: Self.url("/meta/movie/tt1727587.json"))

        #expect(meta["id"] as? String == Self.local + Self.beachDay)
        #expect(meta["type"] as? String == "movie")
        #expect(meta["name"] as? String == "Beach Day")
        #expect((meta["poster"] as? String)?.contains("/Items/\(Self.beachDay)/Images/Primary") == true)
        #expect(cinemetas.status == 404)
    }

    @Test func anUnmatchedShowListsItsEpisodesUnderItsLocalId() async throws {
        let unmatched = Self.server { name, body in
            name == "jellyfin-items-shows" ? body.replacingOccurrences(of: #""Imdb":"tt1748166","#, with: "") : body
        }
        let stub = HTTPStub(unmatched)
        let addon = Self.addon(stub)
        let show = Self.local + Self.pioneerOne

        let shows = try Self.list(try await Self.json(addon, "/catalog/series/a656b907eb3a73532e40e44b968d0225.json"), "metas")
        let meta = try #require(try await Self.json(addon, "/meta/series/\(show).json")["meta"] as? [String: Any])
        let streams = try Self.list(try await Self.json(addon, "/stream/series/\(show)%3A1%3A2.json"), "streams")

        #expect(shows.map { $0["id"] as? String } == [show])
        #expect(meta["name"] as? String == "Pioneer One")
        #expect(meta["releaseInfo"] as? String == "2010")
        let videos = try Self.list(meta, "videos")
        #expect(videos.map { $0["id"] as? String } == ["\(show):1:1", "\(show):1:2", "\(show):1:3"])
        #expect(videos.map { $0["title"] as? String } == ["Earthfall", "The Man From Mars", "Alone in the Night"])
        #expect(streams.count == 1)
        #expect(stub.requests.last?.query("Ids") == Self.pioneerOneS01E02)
    }

    @Test func aMovieStreamsItsFileUnderAPlaceholder() async throws {
        let stub = HTTPStub(Self.server())
        let addon = Self.addon(stub)

        let streams = try Self.list(try await Self.json(addon, "/stream/movie/tt1727587.json"), "streams")

        #expect(stub.requests.last?.query("Ids") == Self.sintel)
        let stream = try #require(streams.first)
        #expect(streams.count == 1)
        #expect(stream["url"] as? String == "\(Self.root)/play/\(Self.sintel)/\(Self.sintel)")
        #expect(stream["name"] as? String == "Living Room")
        #expect(stream["description"] as? String == "Sintel (2010).mkv\n720p H264 SDR")
        let hints = try #require(stream["behaviorHints"] as? [String: Any])
        #expect(hints["filename"] as? String == "Sintel (2010).mkv")
        #expect(hints["videoSize"] as? Int == 6_813_530)
    }

    @Test func anEpisodeStreamsTheFileWithItsSeasonAndNumber() async throws {
        let stub = HTTPStub(Self.server())
        let addon = Self.addon(stub)

        let streams = try Self.list(try await Self.json(addon, "/stream/series/tt1748166%3A1%3A2.json"), "streams")

        #expect(stub.requests.last?.query("Ids") == Self.pioneerOneS01E02)
        #expect(streams.map { $0["url"] as? String } == ["\(Self.root)/play/\(Self.pioneerOneS01E02)/\(Self.pioneerOneS01E02)"])
        #expect(streams.map { ($0["behaviorHints"] as? [String: Any])?["filename"] as? String } == ["Pioneer One S01E02.mkv"])
    }

    @Test func aTitleTheServerLacksHasNoStreamsAndAsksNothing() async throws {
        let stub = HTTPStub(Self.server())
        let addon = Self.addon(stub)

        let movie = try Self.list(try await Self.json(addon, "/stream/movie/tt0111161.json"), "streams")
        let episode = try Self.list(try await Self.json(addon, "/stream/series/tt1748166%3A1%3A9.json"), "streams")

        #expect(movie.isEmpty && episode.isEmpty)
        #expect(stub.requests.allSatisfy { $0.query("Ids") == nil })
    }

    @Test func subtitlesBesideTheFileAreOffered() async throws {
        let addon = Self.addon(HTTPStub(Self.server()))

        let subtitles = try Self.list(try await Self.json(addon, "/subtitles/movie/tt1727587/videoSize=6813530.json"), "subtitles")
        let none = try Self.list(try await Self.json(addon, "/subtitles/series/tt1748166%3A1%3A2.json"), "subtitles")

        #expect(subtitles.map { $0["url"] as? String } == ["\(Self.root)/subtitle/\(Self.sintel)/\(Self.sintel)/0"])
        #expect(subtitles.map { $0["lang"] as? String } == ["eng"])
        #expect(none.isEmpty)
    }

    @Test func placeholdersPlayTheServersFileWithTheTokenInAHeader() throws {
        let addon = Self.addon(HTTPStub(Self.server()))
        let item = try #require(SourceItemID(Self.sintel))
        let video = Self.url("/play/\(Self.sintel)/\(Self.sintel)")
        let subtitle = Self.url("/subtitle/\(Self.sintel)/\(Self.sintel)/0")

        let file = addon.playbackSource(for: try #require(SourcePlaceholder(video)))
        let subtitles = addon.playbackSource(for: try #require(SourcePlaceholder(subtitle)))

        #expect(SourcePlaceholder(video) == .video(item, file: item))
        #expect(file.url.rawValue.absoluteString == "http://jellyfin.local:8096/Videos/\(Self.sintel)/stream?static=true&mediaSourceId=\(Self.sintel)")
        #expect(subtitles.url.rawValue.absoluteString == "http://jellyfin.local:8096/Videos/\(Self.sintel)/\(Self.sintel)/Subtitles/0/Stream.srt")
        for source in [file, subtitles] {
            #expect(source.headers["Authorization"]?.hasSuffix(#"Token="0123456789abcdef0123456789abcdef""#) == true)
            #expect(!source.url.rawValue.absoluteString.contains(Self.session.token))
        }
    }

    @Test func everyCallCarriesTheTokenInAHeaderOnly() async throws {
        let stub = HTTPStub(Self.server())
        let addon = Self.addon(stub)

        _ = try await Self.json(addon, "/stream/movie/tt1727587.json")

        #expect(stub.requests.count == 5)
        for request in stub.requests {
            #expect(request.value(forHTTPHeaderField: "Authorization")?.contains(#"Token="0123456789abcdef0123456789abcdef""#) == true)
            #expect(request.url?.absoluteString.contains(Self.session.token) == false)
        }
    }

    @Test func theIndexIsReadOnceForItsLifetime() async throws {
        let stub = HTTPStub(Self.server())
        let addon = Self.addon(stub)
        let expiring = HTTPStub(Self.server())
        let alwaysOld = Self.addon(expiring, lifetime: .zero)

        async let first = Self.json(addon, "/catalog/movie/f137a2dd21bbc1b99aa5c0f6bf02a805.json")
        async let second = Self.json(addon, "/catalog/series/a656b907eb3a73532e40e44b968d0225.json")
        _ = try await (first, second)
        _ = try await Self.json(addon, "/meta/movie/\(Self.local)\(Self.beachDay).json")
        _ = try await Self.json(alwaysOld, "/catalog/movie/f137a2dd21bbc1b99aa5c0f6bf02a805.json")
        _ = try await Self.json(alwaysOld, "/catalog/movie/f137a2dd21bbc1b99aa5c0f6bf02a805.json")

        #expect(stub.requests.filter { $0.url?.path() == "/Users/u1/Views" }.count == 1)
        #expect(expiring.requests.filter { $0.url?.path() == "/Users/u1/Views" }.count == 2)
    }

    @Test func aFailedReadAnswersAnErrorAndIsTriedAgain() async throws {
        let failing = Mutex(true)
        let healthy = Self.server()
        let stub = HTTPStub { request in
            failing.withLock { $0 } ? HTTPStub.Response(status: 401, body: Data()) : healthy(request)
        }
        let addon = Self.addon(stub)
        let url = Self.url("/catalog/movie/f137a2dd21bbc1b99aa5c0f6bf02a805.json")

        let refused = await addon.respond(to: url)
        failing.withLock { $0 = false }
        let answered = await addon.respond(to: url)

        #expect(refused.status == 502)
        #expect(answered.status == 200)
    }

    @Test func playbackReportsCarryThePositionInTicks() async throws {
        let stub = HTTPStub(Self.server())
        let addon = Self.addon(stub)
        let item = try #require(SourceItemID(Self.sintel))

        await addon.report(JellyfinPlaybackReport(
            kind: .stopped, source: Self.source.id, item: item, file: item, playSession: "s1", position: .milliseconds(31_500), isPaused: false
        ))

        let request = try #require(stub.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/Sessions/Playing/Stopped")
        let sent = try #require(request.body)
        let body = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect(body["ItemId"] as? String == Self.sintel)
        #expect(body["MediaSourceId"] as? String == Self.sintel)
        #expect(body["PlaySessionId"] as? String == "s1")
        #expect(body["PositionTicks"] as? Int == 315_000_000)
    }
}

private final class BundleMarker {}

/// Against the dev Jellyfin server of `scripts/dev-sources.sh up` (`DEV_JELLYFIN_URL`, localhost by default).
struct JellyfinAddonLiveTests {
    private static let environment = ProcessInfo.processInfo.environment
    private static let login = SourceLogin(
        endpoint: SourceEndpoint(environment["DEV_JELLYFIN_URL"] ?? "http://localhost:8196").require(),
        username: SourceUsername(environment["DEV_SOURCES_USER"] ?? "takane").require(),
        password: Password(environment["DEV_SOURCES_PASSWORD"] ?? "takane-dev").require()
    )
    private static let id = SourceID("livetest").require()

    private static func addon() async throws -> JellyfinAddon {
        let client = JellyfinClient(session: .shared, version: "live-test")
        let (name, session) = try await client.signIn(login, for: id)
        let source = MediaSource(id: id, kind: .jellyfin, name: Redacted(name), endpoint: login.endpoint, username: login.username)
        return JellyfinAddon(source: source, session: session, client: client) {}
    }

    private static func json(_ addon: JellyfinAddon, _ path: String) async throws -> [String: Any] {
        let reply = await addon.respond(to: InProcessURL(URL(string: "https://livetest.source.invalid\(path)").require()).require())
        try #require(reply.status == 200, "\(path) answered \(reply.status)")
        return try #require(try JSONSerialization.jsonObject(with: reply.body) as? [String: Any])
    }

    private static func placeholder(_ item: [String: Any]?) -> SourcePlaceholder? {
        (item?["url"] as? String).flatMap(URL.init(string:)).flatMap(InProcessURL.init).flatMap(SourcePlaceholder.init)
    }

    private static func fetch(_ source: PlaybackSource, range: String? = nil) async throws -> (Data, Int) {
        var request = URLRequest(url: source.url.rawValue)
        source.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.setValue(range, forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    @Test(.enabled(if: LiveTests.enabled, "set STREMIO_LIVE_TESTS=1 and run scripts/dev-sources.sh up"))
    func theIndexListsTheDevServersLibraries() async throws {
        let addon = try await Self.addon()

        let index = try await addon.index()

        #expect(index.libraries.map(\.name.rawValue).sorted() == ["Home Videos", "Movies", "Shows"])
        let movies = try #require(index.libraries.first { $0.name.rawValue == "Movies" })
        #expect(Set(movies.titles.map(\.id.rawValue)) == ["tt1727587", "tt1254207", "tt2285752", "tt0807840"])
        #expect(index.items[PlayableID("tt1748166:1:2").require()]?.count == 1)
        #expect(index.localTitles.values.map(\.name.rawValue) == ["Beach Day"])
    }

    @Test(.enabled(if: LiveTests.enabled, "set STREMIO_LIVE_TESTS=1 and run scripts/dev-sources.sh up"))
    func sintelPlaysFromItsPlaceholderWithItsSubtitles() async throws {
        let addon = try await Self.addon()

        let streams = try await Self.json(addon, "/stream/movie/tt1727587.json")["streams"] as? [[String: Any]]
        let subtitles = try await Self.json(addon, "/subtitles/movie/tt1727587.json")["subtitles"] as? [[String: Any]]
        let video = try #require(Self.placeholder(streams?.first))
        let srt = try #require(Self.placeholder(subtitles?.first))

        let (bytes, status) = try await Self.fetch(addon.playbackSource(for: video), range: "bytes=0-1023")
        let (text, subtitleStatus) = try await Self.fetch(addon.playbackSource(for: srt))
        #expect(status == 206)
        #expect(bytes.count == 1024)
        #expect(subtitleStatus == 200)
        #expect(String(decoding: text, as: UTF8.self).contains("A subtitle from a sidecar file."))
    }
}
