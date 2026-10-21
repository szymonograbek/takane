import Foundation

/// Skip segments from SkipDB (skipdb.tv), an open API keyed by IMDb id. No account or key.
/// Allows 120 requests a minute.
struct SkipDBSkipSegmentService: SkipSegmentService {
    private static let endpoint = URL(string: "https://api.skipdb.tv/api/segments")

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func segments(for item: PlayableID, duration: Duration) async throws(SkipSegmentError) -> SkipSegments {
        guard let endpoint = Self.endpoint else { throw .unavailable(reason: "invalid SkipDB endpoint") }
        var query = [URLQueryItem(name: "imdb_id", value: item.media.rawValue)]
        if case .episode(_, let season, let episode) = item {
            query += [URLQueryItem(name: "season", value: "\(season)"), URLQueryItem(name: "episode", value: "\(episode)")]
        }
        query.append(URLQueryItem(name: "duration", value: "\(duration.components.seconds)"))
        var request = URLRequest(url: endpoint.appending(queryItems: query))
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response: SkipDBResponse
        do {
            response = try await session.json(SkipDBResponse.self, for: request, decoder: decoder)
        } catch {
            throw Self.portError(error)
        }
        return response.segments(for: item, within: .zero...duration)
    }

    private static func portError(_ failure: HTTPFailure) -> SkipSegmentError {
        switch failure {
        case .status(429): .rateLimited
        case .status(let status): .unavailable(reason: "SkipDB answered HTTP \(status)")
        case .transport(let reason): .unavailable(reason: reason)
        case .decoding(let reason): .unavailable(reason: "unreadable SkipDB response: \(reason)")
        }
    }
}

/// `GET /api/segments`. A kind with no data is `null`; `start_ms` and `end_ms` both 0 confirms the
/// episode has none of that kind.
private struct SkipDBResponse: Decodable {
    struct Segments: Decodable {
        let recap: Segment?
        let intro: Segment?
        let outro: Segment?
        let preview: Segment?
    }

    struct Segment: Decodable {
        let startMs: Int
        let endMs: Int
        /// `exact`, `shifted`, `agnostic` or `out-of-range`.
        let match: String
        let confidence: Double
    }

    let segments: Segments
    let introLengthEstimateMs: Int?

    /// Positions are clamped to `stream`, because shifted timestamps can fall outside it.
    /// Segments left empty, including the "none" marker, are dropped.
    func segments(for item: PlayableID, within stream: ClosedRange<Duration>) -> SkipSegments {
        let found: [SkipSegment] = SegmentKind.allCases.compactMap { kind in
            guard let segment = segment(of: kind) else { return nil }
            return SkipSegment(
                kind: kind, start: .milliseconds(segment.startMs), end: .milliseconds(segment.endMs), within: stream,
                fit: Self.fit(segment.match), confidence: segment.confidence
            )
        }
        return SkipSegments(
            item: item,
            segments: found.sorted { $0.range.lowerBound < $1.range.lowerBound },
            introLengthEstimate: introLengthEstimateMs.map { .milliseconds($0) }
        )
    }

    private func segment(of kind: SegmentKind) -> Segment? {
        switch kind {
        case .recap: segments.recap
        case .intro: segments.intro
        case .outro: segments.outro
        case .preview: segments.preview
        }
    }

    private static func fit(_ match: String) -> SegmentFit {
        switch match {
        case "exact", "shifted": .matched
        case "agnostic": .unknown
        default: .uncertain
        }
    }
}
