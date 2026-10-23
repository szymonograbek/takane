import Foundation
import Synchronization

/// A RapidAPI key, from the app's `RapidAPIKey` Info.plist entry, which the `RAPIDAPI_KEY` build
/// setting fills.
struct RapidAPIKey: Sendable {
    let rawValue: String

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        rawValue = trimmed
    }

    /// Nil in builds made without the key.
    static var bundled: RapidAPIKey? {
        (Bundle.main.object(forInfoDictionaryKey: "RapidAPIKey") as? String).flatMap(RapidAPIKey.init)
    }
}

/// Offers from the Streaming Availability API (movieofthenight.com, through RapidAPI), keyed by IMDb
/// id. Answers are kept for the life of the process, since the key allows few requests a month and
/// every episode of a series shares its show's offers.
final class StreamingAvailabilityWatchOfferService: WatchOfferService {
    private static let host = "streaming-availability.p.rapidapi.com"

    private let key: RapidAPIKey
    private let country: String
    private let session: URLSession
    private let answered = Mutex<[MediaID: [WatchOffer]]>([:])

    /// `country` is an ISO 3166 code, the device's region by default.
    init(key: RapidAPIKey, country: String? = Locale.current.region?.identifier, session: URLSession = .shared) {
        self.key = key
        self.country = (country ?? "us").lowercased()
        self.session = session
    }

    func offers(for title: MediaID) async throws(WatchOfferError) -> [WatchOffer] {
        if let offers = answered.withLock({ $0[title] }) { return offers }
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.path = "/shows/\(title.rawValue)"
        components.queryItems = [URLQueryItem(name: "country", value: country)]
        guard let url = components.url else { throw .unavailable(reason: "invalid Streaming Availability URL for \(title)") }
        var request = URLRequest(url: url)
        request.setValue(key.rawValue, forHTTPHeaderField: "x-rapidapi-key")
        request.setValue(Self.host, forHTTPHeaderField: "x-rapidapi-host")

        let offers: [WatchOffer]
        do {
            offers = try await session.json(StreamingAvailabilityShow.self, for: request, decoder: JSONDecoder()).offers(in: country)
        } catch .status(404), .status(400) {
            // 404 is a title it does not know, 400 a country it does not cover.
            offers = []
        } catch {
            throw Self.portError(error)
        }
        answered.withLock { $0[title] = offers }
        return offers
    }

    private static func portError(_ failure: HTTPFailure) -> WatchOfferError {
        switch failure {
        case .status(429): .rateLimited
        case .status(let status): .unavailable(reason: "Streaming Availability answered HTTP \(status)")
        case .transport(let reason): .unavailable(reason: reason)
        case .decoding(let reason): .unavailable(reason: "unreadable Streaming Availability response: \(reason)")
        }
    }
}

/// `GET /shows/{id}`, the fields offers need. A series lists its show's options, not each episode's.
private struct StreamingAvailabilityShow: Decodable {
    struct Option: Decodable {
        struct Service: Decodable {
            let id: String
            let name: String
        }

        struct Price: Decodable {
            let amount: String
            let formatted: String
        }

        struct Addon: Decodable {
            let name: String
        }

        let service: Service
        /// `subscription`, `free`, `addon`, `rent` or `buy`.
        let type: String
        let link: URL
        let price: Price?
        let addon: Addon?
    }

    let streamingOptions: [String: [Option]]

    /// One offer per service, in the order services first appear, its link the first option's.
    func offers(in country: String) -> [WatchOffer] {
        let options = streamingOptions[country] ?? []
        return options.map(\.service.id).uniqued().compactMap { service in
            let offered = options.filter { $0.service.id == service }
            let access = offered.map(\.type).uniqued().flatMap { type in
                Self.access(type, among: offered.filter { $0.type == type })
            }
            guard let first = offered.first, !access.isEmpty else { return nil }
            return WatchOffer(service: first.service.name, link: first.link, access: access)
        }
    }

    /// Empty for a type this app does not know.
    private static func access(_ type: String, among options: [Option]) -> [WatchOffer.Access] {
        switch type {
        case "subscription": [.subscription]
        case "free": [.free]
        case "addon": options.map { $0.addon?.name }.uniqued().map { WatchOffer.Access.addon(name: $0) }
        case "rent": [.rent(price: lowestPrice(of: options))]
        case "buy": [.buy(price: lowestPrice(of: options))]
        default: []
        }
    }

    private static func lowestPrice(of options: [Option]) -> String? {
        options.compactMap(\.price)
            .compactMap { price in Decimal(string: price.amount).map { (amount: $0, formatted: price.formatted) } }
            .min { $0.amount < $1.amount }?.formatted
    }
}

private extension Array where Element: Hashable {
    /// Without repeats, in first-appearance order.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
