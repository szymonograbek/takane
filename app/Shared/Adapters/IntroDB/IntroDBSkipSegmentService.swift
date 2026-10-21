import Foundation

/// Skip segments from IntroDB (introdb.app), crowdsourced timestamps keyed by IMDb id. Reads are
/// anonymous, with no account or key, and rate limited.
struct IntroDBSkipSegmentService: SkipSegmentService {
    private static let endpoint = URL(string: "https://api.introdb.app/segments")

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func segments(for item: PlayableID, duration: Duration) async throws(SkipSegmentError) -> SkipSegments {
        guard let endpoint = Self.endpoint else { throw .unavailable(reason: "invalid IntroDB endpoint") }
        var query = [URLQueryItem(name: "imdb_id", value: item.media.rawValue)]
        if case .episode(_, let season, let episode) = item {
            query += [URLQueryItem(name: "season", value: "\(season)"), URLQueryItem(name: "episode", value: "\(episode)")]
        } else {
            query.append(URLQueryItem(name: "is_movie", value: "true"))
        }
        var request = URLRequest(url: endpoint.appending(queryItems: query))
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response: IntroDBResponse
        do {
            response = try await session.json(IntroDBResponse.self, for: request, decoder: decoder)
        } catch .status(404) {
            // IntroDB answers 404 for a title it has no data for.
            return SkipSegments(item: item, segments: [], introLengthEstimate: nil)
        } catch {
            throw Self.portError(error)
        }
        return response.segments(for: item, within: .zero...duration)
    }

    private static func portError(_ failure: HTTPFailure) -> SkipSegmentError {
        switch failure {
        case .status(429): .rateLimited
        case .status(let status): .unavailable(reason: "IntroDB answered HTTP \(status)")
        case .transport(let reason): .unavailable(reason: reason)
        case .decoding(let reason): .unavailable(reason: "unreadable IntroDB response: \(reason)")
        }
    }
}

/// `GET /segments`. A kind with no data is `null`. `post_credits` is not decoded: a scene after the
/// credits is something to watch, not to skip.
private struct IntroDBResponse: Decodable {
    struct Segment: Decodable {
        let startMs: Int
        let endMs: Int
        let confidence: Double
    }

    let intro: Segment?
    let recap: Segment?
    let outro: Segment?

    /// IntroDB stores timestamps without a stream length, so each fit is unknown and positions are
    /// clamped to `stream`.
    func segments(for item: PlayableID, within stream: ClosedRange<Duration>) -> SkipSegments {
        let found: [SkipSegment] = SegmentKind.allCases.compactMap { kind in
            guard let segment = segment(of: kind) else { return nil }
            return SkipSegment(
                kind: kind, start: .milliseconds(segment.startMs), end: .milliseconds(segment.endMs), within: stream,
                fit: .unknown, confidence: segment.confidence
            )
        }
        return SkipSegments(item: item, segments: found.sorted { $0.range.lowerBound < $1.range.lowerBound }, introLengthEstimate: nil)
    }

    private func segment(of kind: SegmentKind) -> Segment? {
        switch kind {
        case .recap: recap
        case .intro: intro
        case .outro: outro
        case .preview: nil
        }
    }
}
