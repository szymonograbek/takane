import Foundation

/// What the progress bar marks: where chapters begin, and the parts the viewer may skip.
extension PlayerFeature {
    struct TimelineMarkers: Equatable, Sendable {
        static let none = TimelineMarkers(chapterStarts: [], skippable: [])

        /// Where each chapter after the first begins, as a share of the duration.
        let chapterStarts: [Double]
        /// The offered skip segments, as shares of the duration.
        let skippable: [Range<Double>]
    }
}

extension PlayerFeature.Session {
    /// The skip segments to offer. Those whose timestamps may not fit this cut are left out.
    var offeredSegments: [SkipSegment] {
        segments?.value?.filter { $0.fit != .uncertain } ?? []
    }

    /// The chapter at the displayed position, so a scan names the chapter it has reached. Nil
    /// before the first chapter starts.
    var currentChapter: Chapter? {
        chapters.last { $0.start <= displayedPosition }
    }

    /// None until the duration is known.
    var timelineMarkers: PlayerFeature.TimelineMarkers {
        guard duration > .zero else { return .none }
        let share = { (time: Duration) in min(max(time / duration, 0), 1) }
        return PlayerFeature.TimelineMarkers(
            chapterStarts: chapters.map { share($0.start) }.filter { $0 > 0 && $0 < 1 },
            skippable: offeredSegments.map { share($0.range.lowerBound) ..< share($0.range.upperBound) }.filter { !$0.isEmpty }
        )
    }
}

extension PlayerFeature.State {
    /// The skip segment playing now.
    var activeSegment: SkipSegment? {
        guard let session else { return nil }
        return session.offeredSegments.first { $0.range.contains(session.position) }
    }
}
