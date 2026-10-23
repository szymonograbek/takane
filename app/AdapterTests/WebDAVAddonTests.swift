import Foundation
import Testing

/// A WebDAV source's add-on, answering core from the dev server's recorded listings
/// (`app/AdapterTests/WebDAV`, recorded with curl from `scripts/dev-sources.sh up`) and from
/// listings written here for the folder layouts the dev server lacks.
struct WebDAVAddonTests {
    @Test func eachTopLevelFolderIsASearchableCatalogTypedByWhatItHolds() async throws {
        let stub = HTTPStub(Subject.devServer)
        let addon = Subject.addon(stub)

        let (names, _) = try await Subject.catalogs(addon)

        #expect(names == ["Home Videos movie", "Movies movie", "Shows series"])
        let manifest = try Subject.list(try await Subject.json(addon, "/manifest.json"), "catalogs")
        #expect(manifest.allSatisfy { ($0["extra"] as? [[String: String]]) == [["name": "search"]] })
        #expect(stub.requests.count == 1)
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "PROPFIND")
        #expect(request.value(forHTTPHeaderField: "Depth") == "infinity")
        #expect(request.value(forHTTPHeaderField: "Authorization") == Subject.basic)
        #expect(request.url?.absoluteString == "http://nas.local:8197")
    }

    @Test func taggedTitlesUseTheirIMDbIdAndOthersALocalOne() async throws {
        let addon = Subject.addon(HTTPStub(Subject.devServer))
        let (_, ids) = try await Subject.catalogs(addon)

        let movies = try await Subject.titles(addon, "movie", in: ids["Movies"])
        let shows = try await Subject.titles(addon, "series", in: ids["Shows"])
        let videos = try await Subject.titles(addon, "movie", in: ids["Home Videos"])

        #expect(Set(movies.compactMap { $0["id"] as? String }) == ["tt1727587", "tt1254207", "tt2285752", "tt0807840"])
        let sintel = try #require(movies.first { $0["id"] as? String == "tt1727587" })
        #expect(sintel["name"] as? String == "Sintel")
        #expect(sintel["releaseInfo"] as? String == "2010")
        #expect(sintel["poster"] as? String == "https://images.metahub.space/poster/medium/tt1727587/img")
        #expect(shows.map { $0["id"] as? String } == ["tt1748166"])
        #expect(shows.map { $0["name"] as? String } == ["Pioneer One"])
        let beachDay = try #require(videos.first)
        let beachDayID = try #require(beachDay["id"] as? String)
        #expect(videos.count == 1)
        #expect(beachDayID.hasPrefix(Subject.local) && !beachDayID.contains(":"))
        #expect(beachDay["name"] as? String == "Beach Day")
    }

    @Test func onlyLocalTitlesHaveMetadataHere() async throws {
        let addon = Subject.addon(HTTPStub(Subject.devServer))
        let (_, ids) = try await Subject.catalogs(addon)
        let beachDay = try #require(try await Subject.titles(addon, "movie", in: ids["Home Videos"]).first?["id"] as? String)

        let meta = try #require(try await Subject.json(addon, "/meta/movie/\(beachDay).json")["meta"] as? [String: Any])
        let cinemetas = await addon.respond(to: Subject.url("/meta/movie/tt1727587.json"))

        #expect(meta["name"] as? String == "Beach Day")
        #expect(meta["type"] as? String == "movie")
        #expect(cinemetas.status == 404)
    }

    @Test func searchKeepsTheTitlesWhoseNameHoldsTheQuery() async throws {
        let addon = Subject.addon(HTTPStub(Subject.devServer))
        let (_, ids) = try await Subject.catalogs(addon)

        let found = try await Subject.titles(addon, "movie", in: ids["Movies"], search: "tears%20of")

        #expect(found.map { $0["id"] as? String } == ["tt2285752"])
    }

    @Test func aMovieStreamsItsFileWithBasicAuthenticationInAHeader() async throws {
        let addon = Subject.addon(HTTPStub(Subject.devServer))

        let (stream, plays) = try await Subject.stream(addon, "movie", "tt1727587")

        #expect(stream["name"] as? String == "nas.local")
        let description = try #require(stream["description"] as? String).split(separator: "\n")
        #expect(description.first == "Sintel (2010).mkv")
        #expect(description.count == 2 && description.last?.hasSuffix("MB") == true)
        #expect((stream["behaviorHints"] as? [String: Any])?["videoSize"] as? Int == 6_813_530)
        #expect(plays.url.rawValue.absoluteString == "http://nas.local:8197/Movies/Sintel%20(2010)%20%5Bimdbid-tt1727587%5D/Sintel%20(2010).mkv")
        #expect(plays.headers == ["Authorization": Subject.basic])
        #expect(plays.url.rawValue.user() == nil && plays.url.rawValue.password() == nil)
    }

    @Test func sidecarSubtitlesAreOfferedWithTheirLanguage() async throws {
        let addon = Subject.addon(HTTPStub(Subject.devServer))

        let subtitles = try Subject.list(try await Subject.json(addon, "/subtitles/movie/tt1727587/videoSize=6813530.json"), "subtitles")
        let none = try Subject.list(try await Subject.json(addon, "/subtitles/movie/tt1254207.json"), "subtitles")

        let subtitle = try #require(subtitles.first)
        #expect(subtitles.count == 1 && none.isEmpty)
        #expect(subtitle["lang"] as? String == "eng")
        let plays = try Subject.plays(addon, subtitle)
        #expect(plays.url.rawValue.lastPathComponent == "Sintel (2010).en.srt")
        #expect(plays.headers == ["Authorization": Subject.basic])
    }

    @Test func anEpisodePlaysTheFileWithItsSeasonAndNumber() async throws {
        let addon = Subject.addon(HTTPStub(Subject.devServer))

        let (stream, plays) = try await Subject.stream(addon, "series", "tt1748166%3A1%3A3")
        let missing = try Subject.list(try await Subject.json(addon, "/stream/series/tt1748166%3A1%3A4.json"), "streams")

        #expect((stream["behaviorHints"] as? [String: Any])?["filename"] as? String == "Pioneer One S01E03.mkv")
        #expect(plays.url.rawValue.path() == "/Shows/Pioneer%20One%20(2010)%20%5Bimdbid-tt1748166%5D/Season%2001/Pioneer%20One%20S01E03.mkv")
        #expect(missing.isEmpty)
    }

    @Test func aLocalVideoStreamsUnderItsOwnId() async throws {
        let addon = Subject.addon(HTTPStub(Subject.devServer))
        let (_, ids) = try await Subject.catalogs(addon)
        let beachDay = try #require(try await Subject.titles(addon, "movie", in: ids["Home Videos"]).first?["id"] as? String)

        let (_, plays) = try await Subject.stream(addon, "movie", beachDay)

        #expect(plays.url.rawValue.absoluteString == "http://nas.local:8197/Home%20Videos/Beach%20Day.mp4")
    }
}

/// Folder layouts the dev server lacks, and servers unlike it.
struct WebDAVListingTests {
    @Test func untaggedShowsAreTheFolderAboveTheirSeasons() async throws {
        let addon = Subject.addon(HTTPStub(Subject.listing([
            "/", "/Shows/", "/Shows/Drama/", "/Shows/Drama/Some Show (2001)/", "/Shows/Drama/Some Show (2001)/Season 02/",
            "/Shows/Drama/Some Show (2001)/Season 02/Some Show 2x05 - The Pilot.mkv",
            "/Shows/Drama/Some Show (2001)/Season 02/Some.Show.S02E06.mkv",
            "/Shows/Loose Show S01E01.mkv",
        ])))
        let (names, ids) = try await Subject.catalogs(addon)

        let shows = try await Subject.titles(addon, "series", in: ids["Shows"])
        let someShow = try #require(shows.first { $0["name"] as? String == "Some Show" })
        let id = try #require(someShow["id"] as? String)
        let meta = try #require(try await Subject.json(addon, "/meta/series/\(id).json")["meta"] as? [String: Any])

        #expect(names == ["Shows series"])
        #expect(Set(shows.compactMap { $0["name"] as? String }) == ["Some Show", "Loose Show"])
        #expect(id.hasPrefix(Subject.local) && !id.contains(":"))
        #expect(meta["releaseInfo"] as? String == "2001")
        let videos = try Subject.list(meta, "videos")
        #expect(videos.map { $0["id"] as? String } == ["\(id):2:5", "\(id):2:6"])
        #expect(videos.first?["title"] as? String == "The Pilot")
        let (_, plays) = try await Subject.stream(addon, "series", "\(id)%3A2%3A6")
        #expect(plays.url.rawValue.lastPathComponent == "Some.Show.S02E06.mkv")
    }

    @Test func aFolderIsTheMovieOnlyWhenItHoldsOneVideo() async throws {
        let addon = Subject.addon(HTTPStub(Subject.listing([
            "/", "/Movies/", "/Movies/Lonely (2003)/", "/Movies/Lonely (2003)/lonely-1080p.mkv",
            "/Movies/Collection/", "/Movies/Collection/First (1999).mkv", "/Movies/Collection/Second.avi",
            "/Movies/Collection/notes.txt", "/Photos/", "/Photos/beach.jpg",
        ])))
        let (names, ids) = try await Subject.catalogs(addon)

        let movies = try await Subject.titles(addon, "movie", in: ids["Movies"])

        #expect(names == ["Movies movie"])
        #expect(Set(movies.compactMap { $0["name"] as? String }) == ["Lonely", "First", "Second"])
        #expect(movies.first { $0["name"] as? String == "First" }?["releaseInfo"] as? String == "1999")
    }

    @Test func oddCharactersInNamesSurviveTheListingAndThePlaceholder() async throws {
        let addon = Subject.addon(HTTPStub(Subject.listing([
            "http://nas.local:8197/dav/", "http://nas.local:8197/dav/Movies/",
            "/dav/Movies/100%25%20Real%20%231%3F%20%5Bx%5D%20&amp;%20more.mkv",
            "/dav/Movies/Caf%C3%A9 Cr%C3%A8me (1999) {imdb-tt0123456}.mp4",
            "/elsewhere/Movies/Outside.mkv",
        ])), endpoint: "http://nas.local:8197/dav")
        let (_, ids) = try await Subject.catalogs(addon)

        let movies = try await Subject.titles(addon, "movie", in: ids["Movies"])
        let odd = try #require(movies.first { ($0["id"] as? String)?.hasPrefix(Subject.local) == true })
        let (_, plays) = try await Subject.stream(addon, "movie", try #require(odd["id"] as? String))

        #expect(Set(movies.compactMap { $0["name"] as? String }) == ["100% Real #1? & more", "Café Crème"])
        #expect(movies.contains { $0["id"] as? String == "tt0123456" })
        #expect(plays.url.rawValue.pathComponents == ["/", "dav", "Movies", "100% Real #1? [x] & more.mkv"])
        #expect(plays.url.rawValue.query() == nil && plays.url.rawValue.fragment() == nil)
    }

    @Test func localIdsFollowThePathNotTheServersAddress() async throws {
        let paths = ["/", "/Home Videos/", "/Home Videos/Beach Day.mp4"]
        let here = Subject.addon(HTTPStub(Subject.listing(paths)))
        let there = Subject.addon(HTTPStub(Subject.listing(paths)), endpoint: "http://192.168.1.20:8197")

        let first = try await here.index().localTitles.keys.map(\.rawValue)
        let second = try await there.index().localTitles.keys.map(\.rawValue)

        #expect(first.count == 1 && first == second)
    }

    @Test func aServerRefusingInfiniteDepthIsListedFolderByFolder() async throws {
        let folders = [
            "/": "webdav-propfind-root",
            "/Shows/": "webdav-propfind-shows",
            "/Shows/Pioneer%20One%20(2010)%20%5Bimdbid-tt1748166%5D/": "webdav-propfind-pioneer-one",
            "/Shows/Pioneer%20One%20(2010)%20%5Bimdbid-tt1748166%5D/Season%2001/": "webdav-propfind-season-01",
        ]
        let stub = HTTPStub { request in
            let depth = request.value(forHTTPHeaderField: "Depth")
            let path = request.url.map { $0.path(percentEncoded: true).isEmpty ? "/" : $0.path(percentEncoded: true) } ?? ""
            let normalized = path.hasSuffix("/") ? path : path + "/"
            guard depth == "1", let fixture = folders[normalized] else { return HTTPStub.Response(status: 403, body: Data()) }
            return .json(Subject.recorded(fixture), status: 207)
        }
        let addon = Subject.addon(stub)

        let (names, _) = try await Subject.catalogs(addon)
        let (_, plays) = try await Subject.stream(addon, "series", "tt1748166%3A1%3A2")

        #expect(names == ["Shows series"])
        #expect(plays.url.rawValue.lastPathComponent == "Pioneer One S01E02.mkv")
        #expect(stub.requests.map { $0.value(forHTTPHeaderField: "Depth") }.first == "infinity")
        #expect(stub.requests.filter { $0.value(forHTTPHeaderField: "Depth") == "1" }.count == 6)
    }

    @Test func aHugeShareIsListedOnlyAsDeepAndAsFarAsTheLimits() async throws {
        let shallow = Subject.addon(HTTPStub(Subject.devServer), limits: WebDAVLimits(depth: 2))
        let few = Subject.addon(HTTPStub(Subject.devServer), limits: WebDAVLimits(entries: 3))
        let cut = Subject.addon(HTTPStub(Subject.devServer), limits: WebDAVLimits(answerBytes: 2_500))

        let shallowNames = try await shallow.index().libraries.map(\.name.rawValue)
        let fewNames = try await few.index().libraries.map(\.name.rawValue)
        let cutNames = try await cut.index().libraries.map(\.name.rawValue)

        #expect(shallowNames == ["Home Videos"])
        #expect(fewNames == ["Home Videos"])
        #expect(cutNames == ["Home Videos"])
    }

    @Test func aRefusedPasswordAnswersAnError() async throws {
        let addon = Subject.addon(HTTPStub { _ in HTTPStub.Response(status: 401, body: Data()) })

        await #expect(throws: SourceError.badCredentials) { try await addon.index() }
        #expect(await addon.respond(to: Subject.url("/stream/movie/tt1727587.json")).status == 502)
    }
}

/// The add-on under test, and the servers it lists.
private enum Subject {
    static let root = "https://abcd2345.source.invalid"
    static let local = "takane-abcd2345-"
    static let basic = "Basic dGFrYW5lOnNlY3JldA=="

    static func source(_ endpoint: String = "http://nas.local:8197") -> MediaSource {
        MediaSource(
            id: SourceID("abcd2345").require(), kind: .webDAV, name: SourceName("nas.local").require(),
            endpoint: SourceEndpoint(endpoint).require(), username: SourceUsername("takane").require()
        )
    }

    /// The dev server, which lists the whole folder at once.
    static let devServer: @Sendable (URLRequest) -> HTTPStub.Response = { request in
        request.url?.path() == "" && request.value(forHTTPHeaderField: "Depth") == "infinity"
            ? .json(recorded("webdav-propfind-infinity"), status: 207)
            : HTTPStub.Response(status: 404, body: Data())
    }

    /// A server that lists only these paths, all at once.
    static func listing(_ paths: [String]) -> @Sendable (URLRequest) -> HTTPStub.Response {
        { _ in .json(multistatus(paths), status: 207) }
    }

    /// A multi-status naming each path, a folder when it ends in `/`.
    static func multistatus(_ paths: [String]) -> String {
        let responses = paths.map { path in
            let type = path.hasSuffix("/") ? "<d:collection/>" : ""
            return "<d:response><d:href>\(path)</d:href><d:propstat><d:prop><d:resourcetype>\(type)</d:resourcetype>"
                + "<d:getcontentlength>1000</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>"
        }
        return #"<?xml version="1.0" encoding="utf-8"?><d:multistatus xmlns:d="DAV:">"# + responses.joined() + "</d:multistatus>"
    }

    static func recorded(_ name: String) -> String {
        let url = Bundle(for: BundleMarker.self).url(forResource: name, withExtension: "xml").require()
        return (try? String(contentsOf: url, encoding: .utf8)).require()
    }

    static func addon(_ stub: HTTPStub, endpoint: String = "http://nas.local:8197", limits: WebDAVLimits = WebDAVLimits()) -> WebDAVAddon {
        WebDAVAddon(
            source: source(endpoint), password: Password("secret").require(), client: WebDAVClient(session: stub.session, limits: limits)
        ) {}
    }

    static func url(_ path: String) -> InProcessURL {
        InProcessURL(URL(string: root + path).require()).require()
    }

    static func json(_ addon: WebDAVAddon, _ path: String) async throws -> [String: Any] {
        let reply = await addon.respond(to: url(path))
        try #require(reply.status == 200, "\(path) answered \(reply.status)")
        return try #require(try JSONSerialization.jsonObject(with: reply.body) as? [String: Any])
    }

    static func list(_ object: [String: Any], _ key: String) throws -> [[String: Any]] {
        try #require(object[key] as? [[String: Any]])
    }

    /// The catalogs, as `name type` and their ids by name.
    static func catalogs(_ addon: WebDAVAddon) async throws -> (names: [String], ids: [String: String]) {
        let catalogs = try list(try await json(addon, "/manifest.json"), "catalogs")
        _ = try await addon.index()
        let read = try list(try await json(addon, "/manifest.json"), "catalogs")
        #expect(catalogs.isEmpty)
        let names = read.compactMap { catalog in (catalog["name"] as? String).map { "\($0) \(catalog["type"] as? String ?? "?")" } }
        let ids = Dictionary(read.compactMap { catalog in (catalog["name"] as? String).map { ($0, catalog["id"] as? String ?? "") } }) { first, _ in first }
        return (names, ids)
    }

    static func titles(_ addon: WebDAVAddon, _ type: String, in catalog: String?, search: String? = nil) async throws -> [[String: Any]] {
        let id = try #require(catalog)
        let extra = search.map { "/search=\($0)" } ?? ""
        return try list(try await json(addon, "/catalog/\(type)/\(id)\(extra).json"), "metas")
    }

    /// What the add-on's first stream for `id` plays.
    static func stream(_ addon: WebDAVAddon, _ type: String, _ id: String) async throws -> (stream: [String: Any], plays: PlaybackSource) {
        let streams = try list(try await json(addon, "/stream/\(type)/\(id).json"), "streams")
        let stream = try #require(streams.first)
        #expect(streams.count == 1)
        return (stream, try plays(addon, stream))
    }

    static func plays(_ addon: WebDAVAddon, _ item: [String: Any]) throws -> PlaybackSource {
        let url = try #require((item["url"] as? String).flatMap(URL.init(string:)).flatMap(InProcessURL.init))
        let placeholder = try #require(SourcePlaceholder(url))
        return try #require(addon.playbackSource(for: placeholder))
    }
}

private final class BundleMarker {}

/// Against the dev WebDAV server of `scripts/dev-sources.sh up` (`DEV_WEBDAV_URL`, localhost by default).
struct WebDAVAddonLiveTests {
    private static let environment = ProcessInfo.processInfo.environment
    private static let source = MediaSource(
        id: SourceID("livetest").require(), kind: .webDAV, name: SourceName("Dev WebDAV").require(),
        endpoint: SourceEndpoint(environment["DEV_WEBDAV_URL"] ?? "http://localhost:8197").require(),
        username: SourceUsername(environment["DEV_SOURCES_USER"] ?? "takane").require()
    )
    private static let password = Password(environment["DEV_SOURCES_PASSWORD"] ?? "takane-dev").require()

    private static func addon() -> WebDAVAddon {
        WebDAVAddon(source: source, password: password, client: WebDAVClient(session: .shared)) {}
    }

    private static func json(_ addon: WebDAVAddon, _ path: String) async throws -> [String: Any] {
        let reply = await addon.respond(to: InProcessURL(URL(string: "https://livetest.source.invalid\(path)").require()).require())
        try #require(reply.status == 200, "\(path) answered \(reply.status)")
        return try #require(try JSONSerialization.jsonObject(with: reply.body) as? [String: Any])
    }

    private static func plays(_ addon: WebDAVAddon, _ item: [String: Any]?) throws -> PlaybackSource {
        let url = try #require((item?["url"] as? String).flatMap(URL.init(string:)).flatMap(InProcessURL.init))
        let placeholder = try #require(SourcePlaceholder(url))
        return try #require(addon.playbackSource(for: placeholder))
    }

    private static func fetch(_ source: PlaybackSource, range: String? = nil) async throws -> (Data, Int) {
        var request = URLRequest(url: source.url.rawValue)
        source.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.setValue(range, forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    @Test(.enabled(if: LiveTests.enabled, "set STREMIO_LIVE_TESTS=1 and run scripts/dev-sources.sh up"))
    func theIndexListsTheDevFoldersTitles() async throws {
        let index = try await Self.addon().index()

        #expect(index.libraries.map(\.name.rawValue) == ["Home Videos", "Movies", "Shows"])
        let movies = try #require(index.libraries.first { $0.name.rawValue == "Movies" })
        #expect(Set(movies.titles.map(\.id.rawValue)) == ["tt1727587", "tt1254207", "tt2285752", "tt0807840"])
        #expect(index.items[PlayableID("tt1748166:1:3").require()]?.count == 1)
        #expect(index.localTitles.values.map(\.name.rawValue) == ["Beach Day"])
    }

    @Test(.enabled(if: LiveTests.enabled, "set STREMIO_LIVE_TESTS=1 and run scripts/dev-sources.sh up"))
    func sintelPlaysFromItsPlaceholderWithItsSubtitles() async throws {
        let addon = Self.addon()

        let streams = try await Self.json(addon, "/stream/movie/tt1727587.json")["streams"] as? [[String: Any]]
        let subtitles = try await Self.json(addon, "/subtitles/movie/tt1727587.json")["subtitles"] as? [[String: Any]]
        let video = try Self.plays(addon, streams?.first)
        let srt = try Self.plays(addon, subtitles?.first)

        let (bytes, status) = try await Self.fetch(video, range: "bytes=0-1023")
        let (text, subtitleStatus) = try await Self.fetch(srt)
        #expect(status == 206)
        #expect(bytes.count == 1024)
        #expect(subtitleStatus == 200)
        #expect(String(decoding: text, as: UTF8.self).contains("A subtitle from a sidecar file."))
    }
}
