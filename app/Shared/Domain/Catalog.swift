import Foundation

/// An add-on content type: "movie", "series", "channel", "tv" or anything an add-on declares.
struct ContentType: Hashable, Sendable, CustomStringConvertible {
    static let movie = ContentType(known: "movie")
    static let series = ContentType(known: "series")

    let rawValue: String

    init?(_ rawValue: String) {
        guard !rawValue.isEmpty, !rawValue.contains(where: \.isWhitespace) else { return nil }
        self.rawValue = rawValue
    }

    private init(known rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }
}

/// One catalog of one add-on, as its manifest declares it.
struct CatalogID: Hashable, Sendable {
    let addon: ManifestURL
    let type: ContentType
    let id: String
}

enum PosterShape: Hashable, Sendable {
    case poster
    case landscape
    case square
}

/// A title in a catalog.
struct MetaPreview: Identifiable, Hashable, Sendable {
    let media: MediaID
    let type: ContentType
    let name: String
    let poster: URL?
    let posterShape: PosterShape
    let background: URL?
    let logo: URL?
    let releaseInfo: String?
    let description: String?

    var id: MediaID { media }
}

enum CatalogError: Error, Equatable, Sendable {
    case addonFailed(reason: String)
}

/// One catalog's titles. A failing add-on fails its own row, never the board or the search.
struct CatalogRow: Identifiable, Equatable, Sendable {
    let id: CatalogID
    let addonName: String
    /// The catalog's name from the manifest, such as "Popular", or the add-on's name when it has none.
    let name: String
    /// Pages loaded so far, flattened, each title once. `.loading` until the first page answers;
    /// a catalog that answered with nothing is `.loaded([])`.
    let items: Remote<[MetaPreview], CatalogError>
    /// `CatalogService.loadMore` would fetch another page.
    let canLoadMore: Bool
}

/// The home screen's rows.
enum Board: Equatable, Sendable {
    case loading
    /// No installed add-on offers a catalog; the user has to install one.
    case noCatalogAddons
    case rows([CatalogRow])
}

/// A search query, trimmed and never empty.
struct SearchText: Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        rawValue = trimmed
    }

    var description: String { rawValue }

    /// Where `typed` ends in this text, when this text starts with it and goes on, ignoring letter case.
    func continuation(of typed: SearchText) -> String.Index? {
        guard let match = rawValue.range(of: typed.rawValue, options: [.caseInsensitive, .anchored]),
              match.upperBound < rawValue.endIndex
        else { return nil }
        return match.upperBound
    }
}

enum SearchResults: Equatable, Sendable {
    /// Until the provider took this query; rows then load inside `.rows`.
    case searching(SearchText)
    /// No installed add-on supports search.
    case noSearchAddons
    /// Rows hold the first page of results; `canLoadMore` is always false.
    case rows(SearchText, [CatalogRow])
}

/// One playable video of a title, such as a series episode.
struct Video: Identifiable, Hashable, Sendable {
    let playable: PlayableID
    let name: String
    let season: Int?
    let episode: Int?
    let released: Date?
    let thumbnail: URL?
    let overview: String?
    let isWatched: Bool

    var id: PlayableID { playable }
}

struct TitleDetails: Equatable, Sendable {
    let preview: MetaPreview
    let genres: [String]
    let runtime: String?
    let imdbRating: String?
    /// The add-on's videos whose ids are `PlayableID`s (`tt0944947:1:1`), in its order. Videos with
    /// other ids are left out, so non-IMDb add-ons may list none. Movies usually have none.
    let videos: [Video]
    /// The title as a whole was watched or marked watched. Meaningful for a movie; a series reads
    /// its episodes' marks instead.
    let isWatched: Bool
}

enum DetailsError: Error, Equatable, Sendable {
    /// No installed add-on serves metadata for this type.
    case noMetaAddons
    /// Every add-on that serves it failed or had nothing.
    case notFound
    /// The provider refused the request or did not answer in time.
    case unavailable(reason: String)
}

/// Browses and describes titles across the user's add-ons.
protocol CatalogService: Sendable {
    /// The board now, then after every change, including add-on installs and removals.
    /// Calling it starts loading the rows.
    func board() -> AsyncStream<Board>

    /// Asks a board row for its next page; `board()` reports it. Ignored when the row can't load more.
    func loadMore(_ row: CatalogID)

    /// Results now, then after every change. Finishes when a newer `search(_:)` call replaces this
    /// one: providers may serve one search at a time. Adds `text` to `recentSearches()`.
    func search(_ text: SearchText) -> AsyncStream<SearchResults>

    /// The texts searched, most recent first, now and after every change.
    func recentSearches() -> AsyncStream<[SearchText]>

    /// Forgets every recent search; `recentSearches()` reports it.
    func clearRecentSearches()

    /// Waits for the first add-on that answers with metadata. Providers may share one selection with
    /// `StreamService`, so this can finish a running `streams(for:)` lookup.
    func details(_ media: MediaID, type: ContentType) async throws(DetailsError) -> TitleDetails

    /// The title's details now and after every change while the provider holds them, such as a
    /// video marked watched. Yields nothing while another title's details replace them.
    func detailsChanges(_ media: MediaID, type: ContentType) -> AsyncStream<TitleDetails>
}

extension TitleDetails {
    /// Season numbers in viewing order: regular seasons ascending, then specials (season 0).
    var seasons: [Int] {
        let numbers = Set(videos.compactMap(\.season))
        return numbers.filter { $0 > 0 }.sorted() + (numbers.contains(0) ? [0] : [])
    }

    func episodes(in season: Int) -> [Video] {
        videos.filter { $0.season == season }.sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
    }

    /// What Play starts: the movie, or the first episode of the first regular season.
    var firstPlayable: PlayableID? {
        if preview.type == .movie { return .movie(preview.media) }
        return seasons.first.flatMap { episodes(in: $0).first?.playable }
    }
}
