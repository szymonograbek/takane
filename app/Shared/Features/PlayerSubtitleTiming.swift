import Foundation

/// Moving the subtitles earlier or later while the video plays: a step at a time, so that the
/// line being spoken starts now, or to the delay that lines them up with the speech heard.
extension PlayerFeature {
    enum SubtitleTimingEvent: Sendable {
        /// Moves the subtitles one `step` earlier (backward) or later (forward).
        case nudge(Direction, SubtitleDelay.Step)
        /// "This line starts now": moves the subtitles so the line nearest the playhead starts there.
        case align
        /// Puts the subtitles back where their file times them.
        case reset
        /// The timing strip opened: sample the speech for it until `stopListening`.
        case listen
        case stopListening
        /// What a sample heard around the playhead.
        case heard(SpeechActivity)
        /// Moves the subtitles to the delay on offer, if one is.
        case applySuggestion
    }

    /// What the open timing strip knows of the speech.
    struct HeardSpeech: Equatable, Sendable {
        /// The speech within `speechLaneReach` of the playhead, for its lane.
        var lane = SpeechActivity.empty
        /// The delay that lines the cues up with the speech, from the last sample whose evidence
        /// was clear. A sample at the edge of clear does not take it away, so the offer stays put.
        var suggestion: SubtitleDelay?
    }

    /// How often the open strip samples the speech.
    static let speechSampleInterval = Duration.milliseconds(250)
    /// How far the speech lane reaches either side of the playhead: the alignment window, plus
    /// what the playhead glides between position reports.
    static let speechLaneReach = alignmentWindow + .seconds(1)
    /// How much of the speech before the playhead a suggestion weighs. After it, the engine has
    /// heard a few seconds ahead.
    static let speechEvidenceBefore = Duration.seconds(180)
    static let speechEvidenceAfter = Duration.seconds(15)
    /// How far apart a suggestion and the delay must be for the strip to offer it. Finer than this,
    /// the speech heard cannot tell, and nudging is quicker than reading an offer.
    static let suggestionThreshold = Duration.milliseconds(500)

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
        case .listen:
            heardSpeech = PlayerFeature.HeardSpeech()
            return [.sampleSpeech(speechEvidence)]
        case .stopListening:
            heardSpeech = nil
            return []
        case .heard(let speech) where heardSpeech != nil:
            let lane = position - PlayerFeature.speechLaneReach ..< position + PlayerFeature.speechLaneReach
            let suggestion = PlayerFeature.suggestedDelay(speech: speech, cues: cueTimeline) ?? heardSpeech?.suggestion
            heardSpeech = PlayerFeature.HeardSpeech(lane: speech.slice(lane), suggestion: suggestion)
            return [.sampleSpeech(speechEvidence)]
        case .applySuggestion where subtitleChoice != .off:
            guard let offeredDelay else { return [] }
            return retime(to: offeredDelay)
        case .nudge, .align, .heard, .applySuggestion:
            return []
        }
    }

    /// The suggested delay, while it differs enough from the current one to be worth offering.
    var offeredDelay: SubtitleDelay? {
        guard let suggestion = heardSpeech?.suggestion,
              abs(suggestion.duration - subtitleDelay.duration) >= PlayerFeature.suggestionThreshold else { return nil }
        return suggestion
    }

    private var speechEvidence: Range<Duration> {
        position - PlayerFeature.speechEvidenceBefore ..< position + PlayerFeature.speechEvidenceAfter
    }
}

private func abs(_ duration: Duration) -> Duration {
    duration < .zero ? .zero - duration : duration
}
