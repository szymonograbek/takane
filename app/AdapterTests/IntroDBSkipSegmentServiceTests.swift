import Foundation
import Testing

struct IntroDBSkipSegmentServiceTests {
    /// Recorded from `GET /segments?imdb_id=tt0944947&season=1&episode=1`.
    private static let gameOfThronesPilot = """
    {"imdb_id":"tt0944947","media_type":"tv","is_movie":false,"season":1,"episode":1,\
    "intro":{"start_sec":437,"end_sec":531,"start_ms":437000,"end_ms":531000,"confidence":1,"submission_count":2,\
    "updated_at":"2026-06-16T02:49:39.823Z"},"recap":null,\
    "outro":{"start_sec":3631.5,"end_sec":3699.5,"start_ms":3631500,"end_ms":3699500,"confidence":1,"submission_count":2,\
    "updated_at":"2026-04-08T18:48:22.562Z"},"post_credits":null,"no_intro":false,"no_recap":true,"no_outro":false}
    """

    /// Recorded from `GET /segments?imdb_id=tt0111161&is_movie=true`.
    private static let shawshank = """
    {"imdb_id":"tt0111161","media_type":"movie","is_movie":true,"season":0,"episode":0,"intro":null,"recap":null,\
    "outro":null,"post_credits":null,"no_intro":false,"no_recap":false,"no_outro":false}
    """

    @Test func asksForAnEpisodeAndReturnsItsSegmentsInOrder() async throws {
        let stub = HTTPStub { _ in .json(Self.gameOfThronesPilot) }
        let service = IntroDBSkipSegmentService(session: stub.session)

        let found = try await service.segments(for: Fixture.episode, duration: .seconds(3700))

        #expect(found == SkipSegments(
            item: Fixture.episode,
            segments: [
                SkipSegment(kind: .intro, range: .milliseconds(437_000) ..< .milliseconds(531_000), fit: .unknown, confidence: 1),
                SkipSegment(kind: .outro, range: .milliseconds(3_631_500) ..< .milliseconds(3_699_500), fit: .unknown, confidence: 1),
            ],
            introLengthEstimate: nil
        ))
        let request = try #require(stub.requests.first)
        #expect(request.url?.host() == "api.introdb.app")
        #expect(request.url?.path() == "/segments")
        #expect(request.query("imdb_id") == "tt0944947")
        #expect(request.query("season") == "1")
        #expect(request.query("episode") == "1")
        #expect(request.query("is_movie") == nil)
    }

    @Test func asksForAMovieWithoutSeason() async throws {
        let stub = HTTPStub { _ in .json(Self.shawshank) }
        let service = IntroDBSkipSegmentService(session: stub.session)

        let found = try await service.segments(for: Fixture.movie, duration: .seconds(8520))

        #expect(found == SkipSegments(item: Fixture.movie, segments: [], introLengthEstimate: nil))
        let request = try #require(stub.requests.first)
        #expect(request.query("imdb_id") == "tt0111161")
        #expect(request.query("is_movie") == "true")
        #expect(request.query("season") == nil)
        #expect(request.query("episode") == nil)
    }

    @Test func clampsToAShorterStreamAndSkipsNoPostCreditsScene() async throws {
        let body = """
        {"imdb_id":"tt0944947","media_type":"tv","is_movie":false,"season":1,"episode":1,\
        "intro":{"start_ms":437000,"end_ms":531000,"confidence":0.8},\
        "recap":{"start_ms":0,"end_ms":45000,"confidence":0.6},\
        "outro":{"start_ms":3631500,"end_ms":3699500,"confidence":1},\
        "post_credits":{"start_ms":3650000,"end_ms":3690000,"confidence":1},\
        "no_intro":false,"no_recap":false,"no_outro":false}
        """
        let service = IntroDBSkipSegmentService(session: HTTPStub { _ in .json(body) }.session)

        let found = try await service.segments(for: Fixture.episode, duration: .seconds(3660))

        #expect(found.segments == [
            SkipSegment(kind: .recap, range: .zero ..< .milliseconds(45_000), fit: .unknown, confidence: 0.6),
            SkipSegment(kind: .intro, range: .milliseconds(437_000) ..< .milliseconds(531_000), fit: .unknown, confidence: 0.8),
            SkipSegment(kind: .outro, range: .milliseconds(3_631_500) ..< .seconds(3660), fit: .unknown, confidence: 1),
        ])
    }

    @Test func readsMissingDataAsNoSegments() async throws {
        let stub = HTTPStub { _ in .json(#"{"error":"not found"}"#, status: 404) }
        let service = IntroDBSkipSegmentService(session: stub.session)

        let found = try await service.segments(for: Fixture.movie, duration: .seconds(60))

        #expect(found == SkipSegments(item: Fixture.movie, segments: [], introLengthEstimate: nil))
    }

    @Test(arguments: [
        (429, SkipSegmentError.rateLimited),
        (500, SkipSegmentError.unavailable(reason: "IntroDB answered HTTP 500")),
    ])
    func mapsHTTPFailures(status: Int, expected: SkipSegmentError) async {
        let stub = HTTPStub { _ in .json(#"{"error":"nope"}"#, status: status) }
        let service = IntroDBSkipSegmentService(session: stub.session)

        await #expect(throws: expected) {
            try await service.segments(for: Fixture.movie, duration: .seconds(60))
        }
    }

    @Test(.enabled(if: LiveTests.enabled, "set STREMIO_LIVE_TESTS=1"))
    func liveGameOfThronesPilotHasAnIntro() async throws {
        let found = try await IntroDBSkipSegmentService().segments(for: Fixture.episode, duration: .seconds(3700))

        #expect(found.segments.map(\.kind).contains(.intro))
    }
}
