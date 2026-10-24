import Foundation

/// Moving the subtitles earlier or later while the video plays: a step at a time, or so that the
/// line being spoken starts now.
extension PlayerFeature {
    enum SubtitleTimingEvent: Sendable {
        /// Moves the subtitles one `step` earlier (backward) or later (forward).
        case nudge(Direction, SubtitleDelay.Step)
        /// "This line starts now": moves the subtitles so the line nearest the playhead starts there.
        case align
        /// Puts the subtitles back where their file times them.
        case reset
    }

    /// How far from the playhead "this line starts now" looks for the line.
    static let alignmentWindow = Duration.seconds(10)
    /// What "this line starts now" rounds a delay to, the finest step a press makes.
    static let alignmentPrecision = SubtitleDelay.Step.fine.duration

    /// The cue "this line starts now" moves: of `cues`, the one whose start under `delay` lies
    /// nearest `position`. Nil when none starts within `alignmentWindow` of it.
    static func alignmentTarget(_ cues: [TimedCue], at position: Duration, from delay: SubtitleDelay) -> TimedCue? {
        let nearest = cues.min { distance($0, position, delay) < distance($1, position, delay) }
        guard let nearest, distance(nearest, position, delay) <= alignmentWindow else { return nil }
        return nearest
    }

    /// The delay that starts `cue` at `position`, rounded to `alignmentPrecision`.
    static func delay(starting cue: TimedCue, at position: Duration) -> SubtitleDelay {
        let steps = ((position - cue.range.lowerBound) / alignmentPrecision).rounded()
        return SubtitleDelay(clamping: alignmentPrecision * steps)
    }

    private static func distance(_ cue: TimedCue, _ position: Duration, _ delay: SubtitleDelay) -> Duration {
        abs(cue.range.lowerBound + delay.duration - position)
    }
}

extension PlayerFeature.Session {
    /// The cue "this line starts now" would move now.
    var alignmentTarget: TimedCue? {
        PlayerFeature.alignmentTarget(cueTimeline, at: position, from: subtitleDelay)
    }

    mutating func apply(_ event: PlayerFeature.SubtitleTimingEvent) -> [Effect] {
        switch event {
        case .nudge(let direction, let step) where subtitleChoice != .off:
            return retime(to: subtitleDelay.moved(by: step.duration * direction.sign))
        case .align where subtitleChoice != .off:
            guard let alignmentTarget else { return [] }
            return retime(to: PlayerFeature.delay(starting: alignmentTarget, at: position))
        case .reset:
            return retime(to: .zero)
        case .nudge, .align:
            return []
        }
    }
}

private func abs(_ duration: Duration) -> Duration {
    duration < .zero ? .zero - duration : duration
}
