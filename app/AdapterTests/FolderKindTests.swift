import Foundation
import Synchronization
import Testing

struct FolderKindSuggestionTests {
    struct Library: Sendable, CustomTestStringConvertible {
        let videos: [String]
        let kind: FolderKind

        init(_ videos: [String], _ kind: FolderKind) {
            self.videos = videos
            self.kind = kind
        }

        var testDescription: String { "\(videos) → \(kind)" }
    }

    @Test(arguments: [
        Library(["Show S01E01.mkv", "Show S01E02.mkv", "Sintel (2010).mkv"], .shows),
        Library(["Some Show/Season 1/Some Show 1x01.mkv", "Some Show/Season 1/Some Show 1x02.mkv"], .shows),
        Library(["Sintel (2010).mkv", "Big.Buck.Bunny.2008.1080p.mkv", "Beach Day.mp4"], .movies),
        Library(["Sintel [imdbid-tt1727587]/Sintel.mkv", "Bunny {imdb-tt1254207}.mkv", "Beach Day.mp4"], .movies),
        Library(["Beach Day.mp4", "Sintel (2010).mp4"], .otherVideos),
        Library(["Summer 2019/beach.mp4", "Summer 2019/pool.mp4"], .otherVideos),
        Library(["Beach Day.mp4", "Show S01E01.mkv"], .otherVideos),
        Library(["2019/Birthday.mov"], .otherVideos),
        Library([], .otherVideos),
    ])
    func aLibrarysVideosSuggestItsKind(library: Library) {
        let paths = library.videos.map { WebDAVPath(names: ["Library"] + $0.split(separator: "/").map(String.init)) }

        #expect(WebDAVMatcher.suggestedKind(of: paths) == library.kind)
    }

    @Test func eachLibraryOfTheSourceHasASuggestion() async throws {
        let addon = Subject.addon(HTTPStub(Subject.devServer))

        let suggestions = try await addon.folderSuggestions()

        #expect(suggestions == [
            FolderSuggestion(folder: LibraryFolder("Home Videos").require(), kind: .otherVideos),
            FolderSuggestion(folder: LibraryFolder("Movies").require(), kind: .movies),
            FolderSuggestion(folder: LibraryFolder("Shows").require(), kind: .shows),
        ])
    }
}

/// Which titles are named by Cinemeta's search, by the kind of their folder.
struct FolderKindMatchingTests {
    private static let homeVideos = LibraryFolder("Home Videos").require()
    private static let mixed = LibraryFolder("Mixed").require()

    @Test func aVideoNamedLikeAFilmIsMatchedInMoviesAndStaysLocalInOtherVideos() async throws {
        let paths = ["/", "/Home Videos/", "/Home Videos/Night.of.the.Living.Dead.1968.720p.mkv", "/Home Videos/Beach Day.mp4"]
        let cinemeta = HTTPStub(TitleMatcherTests.cinemeta)
        let asVideos = Subject.addon(HTTPStub(Subject.listing(paths)), titles: TitleMatcherTests.matcher(cinemeta))
        let asMovies = Subject.addon(
            HTTPStub(Subject.listing(paths)), kinds: [Self.homeVideos: .movies], titles: TitleMatcherTests.matcher(HTTPStub(TitleMatcherTests.cinemeta))
        )

        let videos = try await asVideos.index().libraries.flatMap(\.titles).map(\.id.rawValue)
        let movies = try await asMovies.index().libraries.flatMap(\.titles).map(\.id.rawValue)

        #expect(videos.count == 2 && videos.allSatisfy { $0.hasPrefix(Subject.local) })
        #expect(cinemeta.requests.isEmpty)
        #expect(movies.contains("tt0063350") && movies.count == 2)
    }

    @Test func aShowsFolderMatchesOnlyShowsAndAMoviesFolderOnlyFilms() async throws {
        let paths = ["/", "/Mixed/", "/Mixed/Pioneer.One.S01E01.mkv", "/Mixed/Night.of.the.Living.Dead.1968.720p.mkv"]
        let shows = Subject.addon(
            HTTPStub(Subject.listing(paths)), kinds: [Self.mixed: .shows], titles: TitleMatcherTests.matcher(HTTPStub(TitleMatcherTests.cinemeta))
        )
        let movies = Subject.addon(
            HTTPStub(Subject.listing(paths)), kinds: [Self.mixed: .movies], titles: TitleMatcherTests.matcher(HTTPStub(TitleMatcherTests.cinemeta))
        )

        let asShows = try await shows.index().libraries.flatMap(\.titles)
        let asMovies = try await movies.index().libraries.flatMap(\.titles)

        #expect(Set(asShows.map(\.id.rawValue)).contains("tt1748166"))
        #expect(asShows.first { $0.kind == .movie }?.id.rawValue.hasPrefix(Subject.local) == true)
        #expect(Set(asMovies.map(\.id.rawValue)).contains("tt0063350"))
        #expect(asMovies.first { $0.kind == .series }?.id.rawValue.hasPrefix(Subject.local) == true)
    }

    @Test func aFoldersKindTypesItsCatalog() async throws {
        let addon = Subject.addon(
            HTTPStub(Subject.devServer), kinds: [LibraryFolder("Shows").require(): .otherVideos, LibraryFolder("Home Videos").require(): .shows]
        )

        let (names, _) = try await Subject.catalogs(addon)

        #expect(names == ["Home Videos series", "Movies movie", "Shows movie"])
    }

    @Test func taggedTitlesKeepTheirIdsInOtherVideos() async throws {
        let addon = Subject.addon(
            HTTPStub(Subject.listing(["/", "/Home Videos/", "/Home Videos/Sintel (2010) [imdbid-tt1727587].mp4"])),
            kinds: [Self.homeVideos: .otherVideos]
        )

        let ids = try await addon.index().libraries.flatMap(\.titles).map(\.id.rawValue)

        #expect(ids == ["tt1727587"])
    }
}

/// A title's id from its `.nfo` file, its tag, Cinemeta's search or its path, in that order.
struct WebDAVNfoTests {
    /// A server listing `paths` that answers GET for each of `files` with its body, and 500 for others.
    private static func server(_ paths: [String], files: [String: String], sizes: [String: Int] = [:]) -> HTTPStub {
        HTTPStub { request in
            guard request.httpMethod == "GET" else { return .json(Subject.multistatus(paths, sizes: sizes), status: 207) }
            guard let body = request.url.flatMap({ files[$0.path(percentEncoded: false)] }) else { return HTTPStub.Response(status: 500, body: Data()) }
            return .json(body)
        }
    }

    private static func movie(_ id: String) -> String {
        #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><movie><title>Not this</title><uniqueid type="imdb" default="true">\#(id)</uniqueid></movie>"#
    }

    private static func gets(_ stub: HTTPStub) -> [String] {
        stub.requests.filter { $0.httpMethod == "GET" }.compactMap { $0.url?.path(percentEncoded: false) }
    }

    @Test func idsComeFromTheNfoThenTheTagThenTheNameThenThePath() async throws {
        let paths = [
            "/", "/Movies/", "/Movies/Both [imdbid-tt1111111].mkv", "/Movies/Both [imdbid-tt1111111].nfo",
            "/Movies/Night of the Living Dead (1968)/", "/Movies/Night of the Living Dead (1968)/Night.of.the.Living.Dead.1968.720p.mkv",
            "/Movies/Night of the Living Dead (1968)/movie.nfo",
            "/Movies/Tagged [imdbid-tt1254207]/", "/Movies/Tagged [imdbid-tt1254207]/Night.of.the.Living.Dead.1968.720p.mkv",
            "/Movies/Night of the Living Dead 1968 720p/", "/Movies/Night of the Living Dead 1968 720p/Night.of.the.Living.Dead.1968.720p.mkv",
            "/Movies/Unknown (2001).mkv",
        ]
        let files = [
            "/Movies/Both [imdbid-tt1111111].nfo": Self.movie("tt2285752"),
            "/Movies/Night of the Living Dead (1968)/movie.nfo": Self.movie("tt1727587"),
        ]
        let addon = Subject.addon(Self.server(paths, files: files), titles: TitleMatcherTests.matcher(HTTPStub(TitleMatcherTests.cinemeta)))

        let ids = try await addon.index().libraries.flatMap(\.titles).map(\.id.rawValue)

        // Each id can come only from its own source, so five distinct ids show that each title took the first it has.
        #expect(ids.count == 5)
        #expect(Set(ids).isSuperset(of: ["tt2285752", "tt1727587", "tt1254207", "tt0063350"]))
        #expect(ids.contains { $0.hasPrefix(Subject.local) })
    }

    @Test func aShowsNfoNamesItsEpisodesAndAnEpisodesOwnIsNotRead() async throws {
        let paths = [
            "/", "/Shows/", "/Shows/P1/", "/Shows/P1/tvshow.nfo", "/Shows/P1/Season 01/",
            "/Shows/P1/Season 01/P1 S01E04.mkv", "/Shows/P1/Season 01/P1 S01E04.nfo",
        ]
        let files = [
            "/Shows/P1/tvshow.nfo": "<tvshow><title>P1</title><imdbid>tt1748166</imdbid></tvshow>",
            "/Shows/P1/Season 01/P1 S01E04.nfo": #"<episodedetails><uniqueid type="imdb">tt1765474</uniqueid></episodedetails>"#,
        ]
        let stub = Self.server(paths, files: files)
        let addon = Subject.addon(stub)

        let index = try await addon.index()

        #expect(index.libraries.flatMap(\.titles).map(\.id.rawValue) == ["tt1748166"])
        #expect(index.items[PlayableID("tt1748166:1:4").require()]?.count == 1)
        #expect(Self.gets(stub) == ["/Shows/P1/tvshow.nfo"])
    }

    @Test func anNfoThatCannotBeReadLeavesTheTitleAsItWasAndIsReadAgain() async throws {
        let folder = "/Movies/Sintel [imdbid-tt1727587]/"
        let paths = ["/", "/Movies/", folder, folder + "Sintel.mkv", folder + "movie.nfo"]
        let stub = Self.server(paths, files: [:])
        let addon = Subject.addon(stub, lifetime: .zero)

        let first = try await addon.index().libraries.flatMap(\.titles).map(\.id.rawValue)
        _ = try await addon.index()

        #expect(first == ["tt1727587"])
        #expect(Self.gets(stub).count == 2)
    }

    @Test func nfoFilesAreReadOnceUntilTheyChange() async throws {
        let paths = ["/", "/Movies/", "/Movies/Tears of Steel/", "/Movies/Tears of Steel/Tears of Steel.mkv", "/Movies/Tears of Steel/movie.nfo"]
        let size = Mutex(1000)
        let stub = HTTPStub { request in
            guard request.httpMethod == "GET" else {
                return .json(Subject.multistatus(paths, sizes: ["/Movies/Tears of Steel/movie.nfo": size.withLock { $0 }]), status: 207)
            }
            return .json(Self.movie("tt2285752"))
        }
        let nfo = NfoReader()
        let addon = Subject.addon(stub, nfo: nfo, lifetime: .zero)
        let again = Subject.addon(stub, nfo: nfo, lifetime: .zero)

        let ids = try await addon.index().libraries.flatMap(\.titles).map(\.id.rawValue)
        _ = try await addon.index()
        _ = try await again.index()
        let unchanged = Self.gets(stub).count
        size.withLock { $0 = 1001 }
        _ = try await addon.index()

        #expect(ids == ["tt2285752"])
        #expect(unchanged == 1)
        #expect(Self.gets(stub).count == 2)
    }

    @Test func hugeNfoFilesAreNotRead() async throws {
        let paths = [
            "/", "/Movies/", "/Movies/Listed Big/", "/Movies/Listed Big/Listed Big.mkv", "/Movies/Listed Big/movie.nfo",
            "/Movies/Sent Big/", "/Movies/Sent Big/Sent Big.mkv", "/Movies/Sent Big/movie.nfo",
        ]
        let huge = "<movie><imdbid>tt1254207</imdbid>" + String(repeating: "<plot>long</plot>", count: 20_000) + "</movie>"
        let stub = Self.server(
            paths, files: ["/Movies/Listed Big/movie.nfo": Self.movie("tt1727587"), "/Movies/Sent Big/movie.nfo": huge],
            sizes: ["/Movies/Listed Big/movie.nfo": 300_000]
        )
        let addon = Subject.addon(stub)

        let ids = try await addon.index().libraries.flatMap(\.titles).map(\.id.rawValue)

        #expect(ids.count == 2 && ids.allSatisfy { $0.hasPrefix(Subject.local) })
        #expect(Self.gets(stub) == ["/Movies/Sent Big/movie.nfo"])
    }
}

struct KodiNfoTests {
    @Test(arguments: [
        #"<?xml version="1.0" encoding="UTF-8"?><movie><uniqueid type="imdb" default="true">tt2285752</uniqueid></movie>"#,
        "<movie><imdbid>tt2285752</imdbid></movie>",
        "<movie>\n  <id> tt2285752 </id>\n</movie>",
        #"<movie><id>tt1111111</id><uniqueid type="tmdb">133701</uniqueid><uniqueid type="IMDB">tt2285752</uniqueid></movie>"#,
        "<movie><imdbid>tt2285752</imdbid></movie>\nhttps://www.imdb.com/title/tt1111111/",
        "<movie><title>Tears of Steel</title><year>2012</year><imdbid>tt2285752</imdbid><actor><id>tt1111111</id></actor></movie>",
    ])
    func aMovieNfoNamesItsIMDbID(body: String) {
        #expect(KodiNfo.imdbID(in: Data(body.utf8), as: .movie) == MediaID("tt2285752"))
    }

    @Test(arguments: [
        "tt2285752",
        "not xml <imdbid>tt2285752",
        "<movie><title>Tears of Steel</title><year>2012</year></movie>",
        "<movie><imdbid>2285752</imdbid></movie>",
        "<movie><imdbid>tt22</imdbid></movie>",
        "<movie><imdbid>tt2285752x</imdbid></movie>",
        "<movie><imdbid>nm0000123</imdbid></movie>",
        #"<movie><uniqueid type="tmdb">tt2285752</uniqueid></movie>"#,
        "<movie><actor><id>tt2285752</id></actor></movie>",
        "<tvshow><imdbid>tt2285752</imdbid></tvshow>",
        #"<episodedetails><uniqueid type="imdb">tt2285752</uniqueid></episodedetails>"#,
        "",
    ])
    func junkAndOtherIdsNameNoMovie(body: String) {
        #expect(KodiNfo.imdbID(in: Data(body.utf8), as: .movie) == nil)
    }

    @Test func aShowsNfoNamesOnlyAShow() {
        let body = Data("<tvshow><imdbid>tt1748166</imdbid></tvshow>".utf8)

        #expect(KodiNfo.imdbID(in: body, as: .tvshow) == MediaID("tt1748166"))
        #expect(KodiNfo.imdbID(in: Data("<movie><imdbid>tt1748166</imdbid></movie>".utf8), as: .tvshow) == nil)
    }
}

struct SourceStoreListingTests {
    private let id = SourceID("abcd2345").require()

    @Test func aSourceKeptBeforeFoldersHadKindsReadsWithNone() throws {
        let kept = #"{"kind":"webDAV","name":"media","endpoint":"https:\/\/dav.example\/media","username":"takane"}"#

        let source = try #require(KeychainSourceStore.source(id, listed: Data(kept.utf8)))

        #expect(source.name.text.rawValue == "media" && source.kind == .webDAV)
        #expect(source.folderKinds.isEmpty)
    }

    @Test func folderKindsAreKeptAndAnUnknownOneIsLeftOut() throws {
        let kept = #"{"kind":"webDAV","name":"media","endpoint":"https:\/\/dav.example\/media","username":"takane","#
            + #""folderKinds":{"Home Videos":"otherVideos","Anime":"anime"}}"#
        var source = try #require(KeychainSourceStore.source(id, listed: Data(kept.utf8)))
        source.folderKinds[LibraryFolder("Shows").require()] = .shows

        let again = KeychainSourceStore.source(id, listed: try KeychainSourceStore.listing(of: source))

        #expect(source.folderKinds == [LibraryFolder("Home Videos").require(): .otherVideos, LibraryFolder("Shows").require(): .shows])
        #expect(again == source)
    }
}
