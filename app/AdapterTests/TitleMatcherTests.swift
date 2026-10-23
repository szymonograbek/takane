import Foundation
import Testing

struct ReleaseNameTests {
    struct Named: Sendable, CustomTestStringConvertible {
        let name: String
        let title: String
        let year: Int

        init(_ name: String, _ title: String, _ year: Int) {
            self.name = name
            self.title = title
            self.year = year
        }

        var testDescription: String { name }
    }

    @Test(arguments: [
        Named("Sintel (2010)", "Sintel", 2010),
        Named("Sintel (2010) [imdbid-tt1727587]", "Sintel", 2010),
        Named("Sintel.2010.1080p", "Sintel", 2010),
        Named("Big Buck Bunny 2008 1080p", "Big Buck Bunny", 2008),
        Named("Big.Buck.Bunny.2008.1080p", "Big Buck Bunny", 2008),
        Named("The.Matrix.1999.1080p.BluRay.x264-GROUP", "The Matrix", 1999),
        Named("Some_Movie_2015_WEB-DL", "Some Movie", 2015),
        Named("Night of the Living Dead 1968 720p", "Night of the Living Dead", 1968),
        Named("2001 A Space Odyssey (1968)", "2001 A Space Odyssey", 1968),
        Named("1917.2019.2160p.HDR", "1917", 2019),
        Named("Blade.Runner.2049.2017.2160p", "Blade Runner 2049", 2017),
        Named("Amélie (2001) {imdb-tt0211915}", "Amélie", 2001),
    ])
    func aNameWithAYear(named: Named) {
        let parsed = ReleaseName(named.name)
        #expect(parsed.title == named.title)
        #expect(parsed.year == named.year)
    }

    @Test(arguments: [
        ("Pioneer One", "Pioneer One"),
        ("Beach Day", "Beach Day"),
        ("Mr. Robot", "Mr. Robot"),
        ("1917", "1917"),
        ("Blade.Runner.2049.1080p", "Blade Runner 2049"),
        (" - Pilot", "Pilot"),
        (".1080p.WEB-DL", ""),
    ])
    func aNameWithoutAYear(name: String, title: String) {
        let parsed = ReleaseName(name)
        #expect(parsed.title == title)
        #expect(parsed.year == nil)
    }
}

/// Matching on Cinemeta's search, answered from recorded searches (`app/AdapterTests/Cinemeta`,
/// recorded with curl and cut to the fields the matcher reads).
struct TitleMatcherTests {
    @Test func aNameAndYearMatchTheOneTitleWithBoth() async {
        let stub = HTTPStub(Self.cinemeta)
        let matcher = Self.matcher(stub)
        let dead = TitleQuery(kind: .movie, name: "Night of the Living Dead", year: 1968)
        let pioneer = TitleQuery(kind: .series, name: "Pioneer One", year: 2010)

        let found = await matcher.ids(for: [dead, pioneer], within: .seconds(10))

        #expect(found == [dead: MediaID("tt0063350"), pioneer: MediaID("tt1748166")])
        let paths = Set(stub.requests.compactMap { $0.url?.absoluteString })
        #expect(paths == [
            "https://v3-cinemeta.strem.io/catalog/movie/top/search=Night%20of%20the%20Living%20Dead.json",
            "https://v3-cinemeta.strem.io/catalog/series/top/search=Pioneer%20One.json",
        ])
    }

    @Test func aNameWithoutAYearMatchesOnlyTheOneTitleOfThatName() async {
        let matcher = Self.matcher(HTTPStub(Self.cinemeta))
        let pioneer = TitleQuery(kind: .series, name: "pioneer-one", year: nil)
        let dead = TitleQuery(kind: .movie, name: "Night of the Living Dead", year: nil)

        let found = await matcher.ids(for: [pioneer, dead], within: .seconds(10))

        #expect(found == [pioneer: MediaID("tt1748166")])
    }

    @Test(arguments: [
        TitleQuery(kind: .movie, name: "Night of the Living Dead", year: 1969),
        TitleQuery(kind: .series, name: "Pioneer One", year: 2011),
        TitleQuery(kind: .movie, name: "Beach Day", year: nil),
        TitleQuery(kind: .movie, name: "Big Buck Bunny", year: 2008),
    ])
    func noTitleIsGuessed(query: TitleQuery) async {
        let found = await Self.matcher(HTTPStub(Self.cinemeta)).ids(for: [query], within: .seconds(10))

        #expect(found.isEmpty)
    }

    @Test func namesMatchWhateverTheirCaseAccentsAndPunctuation() async {
        let stub = HTTPStub { _ in .json(#"{"metas":[{"id":"tt0211915","name":"Amélie","releaseInfo":"2001"}]}"#) }
        let query = TitleQuery(kind: .movie, name: "AMELIE!", year: 2001)

        #expect(await Self.matcher(stub).ids(for: [query], within: .seconds(10)) == [query: MediaID("tt0211915")])
    }

    @Test func answersAreKeptOnTheDeviceAndAskedOnce() async {
        let suite = "title-matcher-tests-\(UUID().uuidString)"
        let stub = HTTPStub(Self.cinemeta)
        let dead = TitleQuery(kind: .movie, name: "Night of the Living Dead", year: 1968)
        let beach = TitleQuery(kind: .movie, name: "Beach Day", year: nil)

        _ = await Self.matcher(stub, suite: suite).ids(for: [dead, beach], within: .seconds(10))
        let again = await Self.matcher(stub, suite: suite).ids(for: [dead, beach], within: .seconds(10))
        let sameName = await Self.matcher(stub, suite: suite)
            .ids(for: [TitleQuery(kind: .movie, name: "night.of the living dead", year: 1968)], within: .seconds(10))

        #expect(again == [dead: MediaID("tt0063350")])
        #expect(sameName.values.first == MediaID("tt0063350"))
        #expect(stub.requests.count == 2)
    }

    @Test func aTitleNotFoundIsAskedAgainLaterAndAFailedRequestAtOnce() async {
        let failing = HTTPStub { _ in .json("", status: 503) }
        let notFound = HTTPStub(Self.cinemeta)
        let beach = TitleQuery(kind: .movie, name: "Beach Day", year: nil)
        let failingMatcher = Self.matcher(failing)
        let retrying = TitleMatcher(session: notFound.session, defaults: Self.defaults(), retryAfter: .zero)

        _ = await failingMatcher.ids(for: [beach], within: .seconds(10))
        _ = await failingMatcher.ids(for: [beach], within: .seconds(10))
        _ = await retrying.ids(for: [beach], within: .seconds(10))
        _ = await retrying.ids(for: [beach], within: .seconds(10))

        #expect(failing.requests.count == 2)
        #expect(notFound.requests.count == 2)
    }

    @Test func aSlowSearchAnswersALaterCall() async throws {
        let stub = HTTPStub { request in
            Thread.sleep(forTimeInterval: 0.5)
            return Self.cinemeta(request)
        }
        let matcher = Self.matcher(stub)
        let pioneer = TitleQuery(kind: .series, name: "Pioneer One", year: nil)

        let first = await matcher.ids(for: [pioneer], within: .milliseconds(50))
        try await Task.sleep(for: .seconds(1))
        let later = await matcher.ids(for: [pioneer], within: .zero)

        #expect(first.isEmpty)
        #expect(later == [pioneer: MediaID("tt1748166")])
        #expect(stub.requests.count == 1)
    }

    /// Cinemeta as recorded, answering each recorded search and no other.
    static let cinemeta: @Sendable (URLRequest) -> HTTPStub.Response = { request in
        let recorded = [
            "/catalog/movie/top/search=Night of the Living Dead.json": "cinemeta-search-night-of-the-living-dead",
            "/catalog/movie/top/search=Beach Day.json": "cinemeta-search-beach-day",
            "/catalog/movie/top/search=Big Buck Bunny.json": "cinemeta-search-big-buck-bunny",
            "/catalog/series/top/search=Pioneer One.json": "cinemeta-search-pioneer-one",
            "/catalog/series/top/search=pioneer-one.json": "cinemeta-search-pioneer-one",
        ]
        guard let name = request.url.flatMap({ recorded[$0.path()] ?? recorded[$0.path().removingPercentEncoding ?? ""] }),
              let url = Bundle(for: BundleMarker.self).url(forResource: name, withExtension: "json"),
              let body = try? Data(contentsOf: url)
        else { return .json(#"{"metas":[]}"#) }
        return HTTPStub.Response(status: 200, body: body)
    }

    /// `suite` names the defaults the matcher keeps answers in; by default ones of its own.
    static func matcher(_ stub: HTTPStub, suite: String = "title-matcher-tests-\(UUID().uuidString)") -> TitleMatcher {
        TitleMatcher(session: stub.session, defaults: UserDefaults(suiteName: suite).require())
    }

    /// A Cinemeta that knows no title.
    static func knowingNothing() -> TitleMatcher {
        TitleMatcher(session: HTTPStub { _ in .json(#"{"metas":[]}"#) }.session, defaults: defaults())
    }

    /// Defaults of their own, so tests share nothing.
    static func defaults() -> UserDefaults {
        UserDefaults(suiteName: "title-matcher-tests-\(UUID().uuidString)").require()
    }
}

/// Untagged titles named by Cinemeta's search, answered from recorded searches.
struct WebDAVNameMatchingTests {
    static let paths = [
        "/", "/Movies/", "/Movies/Night of the Living Dead 1968 720p/",
        "/Movies/Night of the Living Dead 1968 720p/Night.of.the.Living.Dead.1968.720p.mkv",
        "/Movies/Big Buck Bunny 2008 1080p/Big.Buck.Bunny.2008.1080p.mkv",
        "/Untagged Shows/Pioneer One/Season 1/Pioneer.One.S01E01.mkv",
        "/Home Videos/Beach Day.mp4",
    ]

    @Test func untaggedTitlesCinemetaKnowsTakeItsIdsAndOthersKeepLocalOnes() async throws {
        let addon = Subject.addon(HTTPStub(Subject.listing(Self.paths)), titles: TitleMatcherTests.matcher(HTTPStub(TitleMatcherTests.cinemeta)))
        let (_, ids) = try await Subject.catalogs(addon)

        let movies = try await Subject.titles(addon, "movie", in: ids["Movies"])
        let shows = try await Subject.titles(addon, "series", in: ids["Untagged Shows"])
        let videos = try await Subject.titles(addon, "movie", in: ids["Home Videos"])
        let (episode, plays) = try await Subject.stream(addon, "series", "tt1748166%3A1%3A1")

        let dead = try #require(movies.first { $0["id"] as? String == "tt0063350" })
        #expect(dead["name"] as? String == "Night of the Living Dead")
        #expect(dead["poster"] as? String == "https://images.metahub.space/poster/medium/tt0063350/img")
        let bunny = try #require(movies.first { $0["id"] as? String != "tt0063350" })
        #expect((bunny["id"] as? String)?.hasPrefix(Subject.local) == true)
        #expect(bunny["name"] as? String == "Big Buck Bunny" && bunny["releaseInfo"] as? String == "2008")
        #expect(shows.map { $0["id"] as? String } == ["tt1748166"])
        #expect((videos.first?["id"] as? String)?.hasPrefix(Subject.local) == true)
        #expect((episode["behaviorHints"] as? [String: Any])?["filename"] as? String == "Pioneer.One.S01E01.mkv")
        #expect(plays.url.rawValue.lastPathComponent == "Pioneer.One.S01E01.mkv")
        #expect(await addon.respond(to: Subject.url("/meta/movie/tt0063350.json")).status == 404)
    }

    @Test func aTitleMatchedLaterStillAnswersUnderItsLocalId() async throws {
        let slowCinemeta = HTTPStub { request in
            Thread.sleep(forTimeInterval: 0.3)
            return TitleMatcherTests.cinemeta(request)
        }
        let addon = Subject.addon(
            HTTPStub(Subject.listing(Self.paths)), titles: TitleMatcherTests.matcher(slowCinemeta), matchingBudget: .milliseconds(50), lifetime: .zero
        )

        let before = try await addon.index().libraries.first { $0.name.rawValue == "Movies" }?.titles.map(\.id.rawValue) ?? []
        try await Task.sleep(for: .seconds(2))
        let after = try await addon.index().libraries.first { $0.name.rawValue == "Movies" }?.titles.map(\.id.rawValue) ?? []

        let former = try #require(Set(before).subtracting(after).first)
        #expect(before.count == 2 && before.allSatisfy { $0.hasPrefix(Subject.local) })
        #expect(after.contains("tt0063350") && after.count == 2)
        let meta = try #require(try await Subject.json(addon, "/meta/movie/\(former).json")["meta"] as? [String: Any])
        #expect(meta["name"] as? String == "Night of the Living Dead")
        let (_, plays) = try await Subject.stream(addon, "movie", former)
        #expect(plays.url.rawValue.lastPathComponent == "Night.of.the.Living.Dead.1968.720p.mkv")
    }
}

/// Against Cinemeta itself.
struct TitleMatcherLiveTests {
    @Test(.enabled(if: LiveTests.enabled)) func cinemetaNamesAnUntaggedFilmAndShow() async {
        let matcher = TitleMatcher(session: .shared, defaults: TitleMatcherTests.defaults())
        let dead = TitleQuery(kind: .movie, name: ReleaseName("Night.of.the.Living.Dead.1968.720p").title, year: 1968)
        let pioneer = TitleQuery(kind: .series, name: "Pioneer One", year: nil)

        let found = await matcher.ids(for: [dead, pioneer], within: .seconds(30))

        #expect(found == [dead: MediaID("tt0063350"), pioneer: MediaID("tt1748166")])
    }
}

private final class BundleMarker {}
