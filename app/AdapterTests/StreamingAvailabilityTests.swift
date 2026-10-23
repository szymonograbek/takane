import Foundation
import Testing

struct StreamingAvailabilityTests {
    private static let key = RapidAPIKey("test-key").require()

    /// Trimmed from `GET /shows/tt0111161?country=pl`, with an add-on option added.
    private static let shawshank = """
    {"itemType":"show","showType":"movie","imdbId":"tt0111161","title":"The Shawshank Redemption","streamingOptions":{"pl":[\
    {"service":{"id":"prime","name":"Prime Video"},"type":"rent","link":"https://www.primevideo.com/detail/0H3B",\
    "quality":"uhd","price":{"amount":"14.99","currency":"PLN","formatted":"14.99 PLN"}},\
    {"service":{"id":"prime","name":"Prime Video"},"type":"rent","link":"https://www.primevideo.com/detail/0H3B",\
    "quality":"hd","price":{"amount":"9.99","currency":"PLN","formatted":"9.99 PLN"}},\
    {"service":{"id":"prime","name":"Prime Video"},"type":"buy","link":"https://www.primevideo.com/detail/0H3B",\
    "quality":"uhd","price":{"amount":"39.99","currency":"PLN","formatted":"39.99 PLN"}},\
    {"service":{"id":"prime","name":"Prime Video"},"type":"addon","link":"https://www.primevideo.com/detail/0H3B",\
    "addon":{"id":"hbo","name":"HBO Max"}},\
    {"service":{"id":"netflix","name":"Netflix"},"type":"subscription","link":"https://www.netflix.com/title/70005379"},\
    {"service":{"id":"netflix","name":"Netflix"},"type":"subscription","link":"https://www.netflix.com/title/70005379"}\
    ]}}
    """

    @Test func groupsOptionsByServiceWithTheLowestPrices() async throws {
        let stub = HTTPStub { _ in .json(Self.shawshank) }
        let service = StreamingAvailabilityWatchOfferService(key: Self.key, country: "PL", session: stub.session)

        let offers = try await service.offers(for: Fixture.movie.media)

        #expect(offers == [
            WatchOffer(
                service: "Prime Video", link: URL(string: "https://www.primevideo.com/detail/0H3B").require(),
                access: [.rent(price: "9.99 PLN"), .buy(price: "39.99 PLN"), .addon(name: "HBO Max")]
            ),
            WatchOffer(service: "Netflix", link: URL(string: "https://www.netflix.com/title/70005379").require(), access: [.subscription]),
        ])
        let request = try #require(stub.requests.first)
        #expect(request.url?.host() == "streaming-availability.p.rapidapi.com")
        #expect(request.url?.path() == "/shows/tt0111161")
        #expect(request.query("country") == "pl")
        #expect(request.value(forHTTPHeaderField: "x-rapidapi-key") == "test-key")
    }

    @Test func asksOncePerTitle() async throws {
        let stub = HTTPStub { _ in .json(Self.shawshank) }
        let service = StreamingAvailabilityWatchOfferService(key: Self.key, country: "pl", session: stub.session)

        let first = try await service.offers(for: Fixture.episode.media)
        let second = try await service.offers(for: Fixture.episode.media)

        #expect(first == second)
        #expect(stub.requests.count == 1)
    }

    @Test func hasNoOffersInAnotherCountry() async throws {
        let service = StreamingAvailabilityWatchOfferService(key: Self.key, country: "us", session: HTTPStub { _ in .json(Self.shawshank) }.session)

        #expect(try await service.offers(for: Fixture.movie.media).isEmpty)
    }

    @Test(arguments: [
        (404, #"{"message":"not found"}"#),
        (400, #"{"message":"country \"kz\" is not supported"}"#),
    ])
    func readsAnUnknownTitleOrCountryAsNoOffers(status: Int, body: String) async throws {
        let service = StreamingAvailabilityWatchOfferService(key: Self.key, country: "kz", session: HTTPStub { _ in .json(body, status: status) }.session)

        #expect(try await service.offers(for: Fixture.movie.media).isEmpty)
    }

    @Test(arguments: [
        (429, WatchOfferError.rateLimited),
        (500, WatchOfferError.unavailable(reason: "Streaming Availability answered HTTP 500")),
    ])
    func mapsHTTPFailures(status: Int, expected: WatchOfferError) async {
        let service = StreamingAvailabilityWatchOfferService(
            key: Self.key, country: "us", session: HTTPStub { _ in .json(#"{"message":"nope"}"#, status: status) }.session
        )

        await #expect(throws: expected) {
            try await service.offers(for: Fixture.movie.media)
        }
    }

    @Test(.enabled(if: LiveTests.enabled && ProcessInfo.processInfo.environment["RAPIDAPI_KEY"] != nil, "set STREMIO_LIVE_TESTS=1 and RAPIDAPI_KEY"))
    func liveShawshankIsOfferedInTheUS() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["RAPIDAPI_KEY"].flatMap(RapidAPIKey.init))

        let offers = try await StreamingAvailabilityWatchOfferService(key: key, country: "us").offers(for: Fixture.movie.media)

        #expect(!offers.isEmpty)
    }
}
