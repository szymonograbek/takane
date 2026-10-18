enum SegmentKind: Hashable, Sendable, CaseIterable {
    /// "Previously on".
    case recap
    case intro
    case outro
    /// "Next time on".
    case preview
}

/// How well the stored timestamps fit the stream being played.
enum SegmentFit: Hashable, Sendable {
    /// Fitted to this stream's length.
    case matched
    /// Stored without a length to compare against.
    case unknown
    /// This stream's length differs from the one the timestamps were taken on; offer with caution.
    case uncertain
}

struct SkipSegment: Hashable, Sendable {
    let kind: SegmentKind
    /// Positions in the stream.
    let range: Range<Duration>
    let fit: SegmentFit
    /// 0 to 1.
    let confidence: Double
}

struct SkipSegments: Hashable, Sendable {
    let item: PlayableID
    /// At most one per kind, ordered by start.
    let segments: [SkipSegment]
    /// Typical intro length for the season, for a "skip ~Xs" offer when this episode has no intro yet.
    let introLengthEstimate: Duration?
}

enum SkipSegmentError: Error, Equatable, Sendable {
    case rateLimited
    case unavailable(reason: String)
}

/// Finds the parts of a stream a viewer may want to skip.
protocol SkipSegmentService: Sendable {
    /// `duration` is the stream's length; providers use it to fit timestamps to this cut.
    /// No data is an empty `segments`, not an error.
    func segments(for item: PlayableID, duration: Duration) async throws(SkipSegmentError) -> SkipSegments
}
