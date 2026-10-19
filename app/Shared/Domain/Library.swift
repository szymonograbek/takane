import Foundation

/// A title the user started and has not finished.
struct ContinueWatchingItem: Identifiable, Hashable, Sendable {
    let media: MediaID
    let type: ContentType
    let name: String
    let poster: URL?
    /// Wide artwork, when the provider has it.
    let background: URL?
    /// The movie, or the episode watched last.
    let video: PlayableID
    let offset: Duration
    let duration: Duration

    var id: MediaID { media }
}

/// The user's library as it changes.
protocol LibraryService: Sendable {
    /// Continue watching now, then after every change.
    func continueWatching() -> AsyncStream<[ContinueWatchingItem]>

    /// Forgets the progress on `media`, which takes it out of continue watching.
    func removeFromContinueWatching(_ media: MediaID)

    /// Marks `target` watched or unwatched. A title is marked from its loaded details or, once it
    /// is in the library (as everything in continue watching is), from anywhere. Seasons and videos
    /// are marked only from their title's loaded details. Marking a title watched resets its
    /// progress, which takes it out of continue watching.
    func setWatched(_ target: WatchedTarget, _ isWatched: Bool) throws(WatchedError)
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
