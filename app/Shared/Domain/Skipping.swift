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

extension SkipSegment {
    /// Clamps `start` and `end` to `stream`, because stored timestamps can fall outside it.
    /// Nil when nothing is left between them.
    init?(kind: SegmentKind, start: Duration, end: Duration, within stream: ClosedRange<Duration>, fit: SegmentFit, confidence: Double) {
        let start = min(max(start, stream.lowerBound), stream.upperBound)
        let end = min(max(end, stream.lowerBound), stream.upperBound)
        guard start < end else { return nil }
        self.init(kind: kind, range: start..<end, fit: fit, confidence: confidence)
    }
}

struct SkipSegments: Hashable, Sendable {
    let item: PlayableID
    /// At most one per kind, ordered by start.
    let segments: [SkipSegment]
    /// Typical intro length for the season, for a "skip ~Xs" offer when this episode has no intro yet.
    let introLengthEstimate: Duration?
}

/// The database the player asks for parts to skip.
enum SkipSegmentSource: String, CaseIterable, Hashable, Sendable {
    /// Stremio's own, for Stremio Premium accounts.
    case stremio
    case introDB
    case skipDB

    /// The source without Stremio Premium.
    static let defaults = SkipSegmentSource.introDB

    static func available(hasPremium: Bool) -> [SkipSegmentSource] {
        hasPremium ? allCases : allCases.filter { $0 != .stremio }
    }

    /// The source to use given the one stored, if any: Stremio's when nothing is stored and the
    /// account has Premium, and the source without Premium in place of one no longer available.
    static func resolved(_ stored: SkipSegmentSource?, hasPremium: Bool) -> SkipSegmentSource {
        if let stored, available(hasPremium: hasPremium).contains(stored) { return stored }
        return hasPremium ? .stremio : defaults
    }
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
