/// An item the user started and has not finished.
struct ContinueWatchingItem: Identifiable, Hashable, Sendable {
    let media: MediaID
    let name: String
    let offset: Duration
    let duration: Duration

    var id: MediaID { media }
}

enum Account: Hashable, Sendable {
    case anonymous
    case signedIn(email: String)
}

/// The user's library as it changes.
protocol LibraryService: Sendable {
    /// Continue watching now, then after every change.
    func continueWatching() -> AsyncStream<[ContinueWatchingItem]>

    /// The signed-in account now, then after every change.
    func account() -> AsyncStream<Account>
}
