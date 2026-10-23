import Foundation
import Testing

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
        let titles = TitleMatcher(session: .shared, defaults: TitleMatcherTests.defaults())
        return WebDAVAddon(source: source, password: password, client: WebDAVClient(session: .shared), titles: titles, matchingBudget: .seconds(30)) {}
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

        #expect(index.libraries.map(\.name.rawValue) == ["Home Videos", "Movies", "Shows", "Untagged Shows"])
        let movies = try #require(index.libraries.first { $0.name.rawValue == "Movies" })
        #expect(Set(movies.titles.map(\.id.rawValue)).isSuperset(of: ["tt1727587", "tt1254207", "tt2285752", "tt0807840", "tt0063350"]))
        #expect(index.items[PlayableID("tt1748166:1:3").require()]?.count == 1)
        #expect(index.items[PlayableID("tt1748166:1:1").require()]?.count == 2)
        #expect(Set(index.libraries.flatMap(\.titles).filter { !$0.id.rawValue.hasPrefix("tt") }.map(\.name.rawValue)) == ["Beach Day", "Big Buck Bunny"])
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
