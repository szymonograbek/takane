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
}
