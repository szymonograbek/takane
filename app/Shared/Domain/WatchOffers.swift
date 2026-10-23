import Foundation

/// A streaming service outside this app that has a title.
struct WatchOffer: Hashable, Sendable {
    enum Access: Hashable, Sendable {
        case subscription
        case free
        /// Through a paid channel on the service, such as HBO on Prime Video.
        case addon(name: String?)
        /// `price` is formatted with its currency, the lowest across qualities.
        case rent(price: String?)
        case buy(price: String?)
    }

    let service: String
    /// The title's page on the service.
    let link: URL
    /// Never empty, without duplicates.
    let access: [Access]
}

enum WatchOfferError: Error, Equatable, Sendable {
    case rateLimited
    case unavailable(reason: String)
}

/// Finds where else a title can be watched, in the device's region.
protocol WatchOfferService: Sendable {
    /// One offer per service. A title the provider does not know has no offers, not an error.
    func offers(for title: MediaID) async throws(WatchOfferError) -> [WatchOffer]
}
