import Foundation

/// A title the user started and has not finished, or a show with episodes newer than the one watched.
struct ContinueWatchingItem: Identifiable, Hashable, Sendable {
    let media: MediaID
    let type: ContentType
    let name: Redacted<String>
    let poster: URL?
    /// Wide artwork, when the provider has it.
    let background: URL?
    /// The movie, or the episode watched last.
    let video: PlayableID
    let reason: Reason

    var id: MediaID { media }

    enum Reason: Hashable, Sendable {
        /// The user stopped partway through `video`.
        case partway(offset: Duration, duration: Duration)
        /// `count` episodes came out after `video`, which the user is not partway through.
        case newEpisodes(count: Int)
    }
}

/// The order the library lists its titles in.
enum LibrarySort: CaseIterable, Hashable, Sendable {
    /// Watched or added most recently first.
    case recentlyWatched
    /// A to Z.
    case name
    /// Titles never watched first, then the ones watched longest ago.
    case unwatchedFirst
}

/// Which of the library's titles to list, and in what order.
struct LibraryFilter: Hashable, Sendable {
    /// One type, or every type when nil.
    let type: ContentType?
    let sort: LibrarySort
}

/// The library's titles for one filter.
struct LibraryContents: Equatable, Sendable {
    /// The filter these titles answer.
    let filter: LibraryFilter
    /// The types the library holds, whatever the filter, in the provider's order.
    let types: [ContentType]
    /// The titles loaded so far, in the filter's order. Empty when none matches.
    let titles: [MetaPreview]
    /// `LibraryService.loadMoreLibrary()` would add titles.
    let canLoadMore: Bool
}

/// An episode of a show in the library, with the date it comes out.
struct UpcomingEpisode: Identifiable, Hashable, Sendable {
    let show: MetaPreview
    let video: PlayableID
    let name: Redacted<String>
    let released: Date

    var id: PlayableID { video }
}

/// The user's library as it changes.
protocol LibraryService: Sendable {
    /// Continue watching now, then after every change.
    func continueWatching() -> AsyncStream<[ContinueWatchingItem]>

    /// The library's titles that match `filter` now, then after every change, such as a title added
    /// or removed anywhere. Finishes when a newer `library(_:)` call replaces it: providers may serve
    /// one filter at a time.
    func library(_ filter: LibraryFilter) -> AsyncStream<LibraryContents>

    /// Asks the current `library(_:)` filter for more titles; its stream reports them. Ignored when it
    /// has no more.
    func loadMoreLibrary()

    /// Adds `title` to the library or removes it. Details and the library report the change.
    func setInLibrary(_ title: MetaPreview, _ isInLibrary: Bool)

    /// The library's shows' episodes that come out from the start of the viewer's today on, earliest
    /// first, asked for again on every call so the shows added since are included. Loaded and empty
    /// when no add-on lists episodes by date or the library holds no shows; failed only when every
    /// add-on that lists them failed.
    func upcomingEpisodes() -> AsyncStream<Remote<[UpcomingEpisode], CatalogError>>

    /// Forgets the progress and new episodes of `media`, which takes it out of continue watching.
    func removeFromContinueWatching(_ media: MediaID)

    /// Marks `target` watched or unwatched. A title is marked from its loaded details or, once it
    /// is in the library (as everything in continue watching is), from anywhere. Seasons and videos
    /// are marked only from their title's loaded details. Marking a title watched resets its
    /// progress, which takes it out of continue watching.
    func setWatched(_ target: WatchedTarget, _ isWatched: Bool) throws(WatchedError)

    /// Looks for episodes of the library's shows that came out since each was last watched. Those
    /// shows join continue watching.
    func checkForNewEpisodes()
}

/// What one watched mark covers.
enum WatchedTarget: Hashable, Sendable {
    /// The title as a whole. A series marked this way keeps its episodes' marks.
    case title(MediaID)
    /// Every video of one season of a title.
    case season(MediaID, Int)
    /// One video of a title, such as an episode.
    case video(PlayableID)

    var media: MediaID {
        switch self {
        case .title(let media), .season(let media, _): media
        case .video(let playable): playable.media
        }
    }
}

enum WatchedError: Error, Equatable, Sendable {
    /// The provider holds another title's details, which seasons and videos are marked through.
    case titleNotLoaded
    /// The loaded details list no such video or season.
    case notFound
    /// The provider refused the mark.
    case unavailable(reason: String)
}
