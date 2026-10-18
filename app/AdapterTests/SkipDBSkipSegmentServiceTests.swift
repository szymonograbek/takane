import Foundation
import Testing

struct SkipDBSkipSegmentServiceTests {
    /// Recorded from `GET /api/segments?imdb_id=tt0944947&season=1&episode=1&duration=3700`.
    private static let gameOfThronesPilot = """
    {"imdb_id":"tt0944947","season":1,"episode":1,"segments":{\
    "intro":{"start_ms":447800,"end_ms":461400,"adjusted":false,"offset_ms":0,"match":"exact","confidence":0.9},\
    "recap":{"start_ms":-2100,"end_ms":57300,"adjusted":true,"offset_ms":-2100,"match":"shifted","confidence":0.82},\
    "outro":{"start_ms":3629500,"end_ms":3699200,"adjusted":false,"offset_ms":0,"match":"exact","confidence":0.91},\
    "preview":null},"intro_length_estimate_ms":null}
    """

    /// Recorded from `GET /api/segments?imdb_id=tt0111161&duration=8520`.
    private static let shawshank = """
    {"imdb_id":"tt0111161","season":null,"episode":null,"segments":{"intro":null,"recap":null,\
    "outro":{"start_ms":8331300,"end_ms":8552600,"adjusted":false,"offset_ms":-32600,"match":"out-of-range","confidence":0.6},\
    "preview":null},"intro_length_estimate_ms":null}
    """

    @Test func fitsAnEpisodesSegmentsToTheStreamInOrder() async throws {
        let stub = HTTPStub { _ in .json(Self.gameOfThronesPilot) }
        let service = SkipDBSkipSegmentService(session: stub.session)

        let found = try await service.segments(for: Fixture.episode, duration: .seconds(3700))

        #expect(found == SkipSegments(
            item: Fixture.episode,
            segments: [
                SkipSegment(kind: .recap, range: .zero ..< .milliseconds(57300), fit: .matched, confidence: 0.82),
                SkipSegment(kind: .intro, range: .milliseconds(447_800) ..< .milliseconds(461_400), fit: .matched, confidence: 0.9),
                SkipSegment(kind: .outro, range: .milliseconds(3_629_500) ..< .milliseconds(3_699_200), fit: .matched, confidence: 0.91),
            ],
            introLengthEstimate: nil
        ))
        let request = try #require(stub.requests.first)
        #expect(request.url?.path() == "/api/segments")
        #expect(request.query("imdb_id") == "tt0944947")
        #expect(request.query("season") == "1")
        #expect(request.query("episode") == "1")
        #expect(request.query("duration") == "3700")
    }

    @Test func asksForAMovieWithoutSeasonAndClampsToItsLength() async throws {
        let stub = HTTPStub { _ in .json(Self.shawshank) }
        let service = SkipDBSkipSegmentService(session: stub.session)

        let found = try await service.segments(for: Fixture.movie, duration: .seconds(8520))

        #expect(found.segments == [
            SkipSegment(kind: .outro, range: .milliseconds(8_331_300) ..< .seconds(8520), fit: .uncertain, confidence: 0.6),
        ])
        let request = try #require(stub.requests.first)
        #expect(request.query("imdb_id") == "tt0111161")
        #expect(request.query("season") == nil)
        #expect(request.query("episode") == nil)
    }

    @Test func dropsConfirmedAbsentAndReversedSegments() async throws {
        let body = """
        {"imdb_id":"tt0903747","season":1,"episode":1,"segments":{\
        "intro":{"start_ms":229500,"end_ms":246500,"adjusted":false,"offset_ms":0,"match":"agnostic","confidence":0.75},\
        "recap":{"start_ms":0,"end_ms":0,"adjusted":false,"offset_ms":0,"match":"exact","confidence":1},\
        "outro":{"start_ms":3500000,"end_ms":3434000,"adjusted":false,"offset_ms":0,"match":"exact","confidence":0.9},\
        "preview":{"start_ms":3440000,"end_ms":3460000,"adjusted":false,"offset_ms":0,"match":"fuzzy","confidence":0.5}},\
        "intro_length_estimate_ms":17000}
        """
        let service = SkipDBSkipSegmentService(session: HTTPStub { _ in .json(body) }.session)

        let found = try await service.segments(for: Fixture.episode, duration: .seconds(3480))

        #expect(found.segments == [
            SkipSegment(kind: .intro, range: .milliseconds(229_500) ..< .milliseconds(246_500), fit: .unknown, confidence: 0.75),
            SkipSegment(kind: .preview, range: .milliseconds(3_440_000) ..< .milliseconds(3_460_000), fit: .uncertain, confidence: 0.5),
        ])
        #expect(found.introLengthEstimate == .milliseconds(17000))
    }

    @Test(arguments: [
        (429, SkipSegmentError.rateLimited),
        (500, SkipSegmentError.unavailable(reason: "SkipDB answered HTTP 500")),
    ])
    func mapsHTTPFailures(status: Int, expected: SkipSegmentError) async {
        let stub = HTTPStub { _ in .json(#"{"error":"nope"}"#, status: status) }
        let service = SkipDBSkipSegmentService(session: stub.session)

        await #expect(throws: expected) {
            try await service.segments(for: Fixture.movie, duration: .seconds(60))
        }
    }

    @Test(.enabled(if: LiveTests.enabled, "set STREMIO_LIVE_TESTS=1"))
    func liveGameOfThronesPilotHasAnIntroAndARecap() async throws {
        let found = try await SkipDBSkipSegmentService().segments(for: Fixture.episode, duration: .seconds(3700))

        #expect(Set(found.segments.map(\.kind)).isSuperset(of: [.intro, .recap]))
    }
}
