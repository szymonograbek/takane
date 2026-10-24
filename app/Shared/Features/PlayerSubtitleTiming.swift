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
        /// The timing strip opened: hear the speech for its lane until `stopListening`.
        case listen
        case stopListening
        /// What a sample heard around the playhead.
        case heard(SpeechActivity)
        /// Moves the subtitles to the delay on offer, if one is.
        case applySuggestion
    }

    /// What the player knows of the speech heard.
    struct SpeechTiming: Equatable, Sendable {
        /// The speech within `speechLaneReach` of the playhead, while the timing strip is open.
        var lane: SpeechActivity?
        /// The delay that lines the cues up with the speech, once a sample's evidence was clear.
        /// Kept, since the player stops hearing once it has one, and a sample at the edge of clear
        /// does not take it away.
        var suggestion: Suggestion?
    }

    /// A suggested delay, for the subtitle track that showed when it was found.
    struct Suggestion: Equatable, Sendable {
        let subtitles: MediaTrack.ID
        let delay: SubtitleDelay
    }

    /// How often the open strip samples the speech.
    static let speechSampleInterval = Duration.milliseconds(250)
    /// How often the speech is sampled for a suggestion while the strip is closed.
    static let speechBackgroundInterval = Duration.seconds(5)
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

extension PlayerFeature {
    /// Hears speech only while `Session.hearsSpeech` says so: whatever an event changes (the
    /// subtitles, the strip, a suggestion found, a new session), this starts or stops it once.
    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        let wasHearing = state.session?.hearsSpeech ?? false
        let effects = reduceEvent(&state, event)
        let session = state.session
        let isHearing = session?.hearsSpeech ?? false
        guard isHearing != wasHearing else { return effects }
        guard isHearing, let session else { return effects + [.hearSpeech(false)] }
        let sampling = effects.contains { if case .sampleSpeech = $0 { true } else { false } }
        return effects + [.hearSpeech(true)] + (sampling ? [] : [session.nextSpeechSample])
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
            speech.lane = .empty
            return [.sampleSpeech(speechEvidence, after: .zero)]
        case .stopListening:
            speech.lane = nil
            return []
        case .heard(let heard) where hearsSpeech:
            if let shownSubtitles, let delay = PlayerFeature.suggestedDelay(speech: heard, cues: cueTimeline) {
                speech.suggestion = PlayerFeature.Suggestion(subtitles: shownSubtitles, delay: delay)
            }
            if speech.lane != nil {
                speech.lane = heard.slice(position - PlayerFeature.speechLaneReach ..< position + PlayerFeature.speechLaneReach)
            }
            return hearsSpeech ? [nextSpeechSample] : []
        case .applySuggestion where subtitleChoice != .off:
            guard let offeredDelay else { return [] }
            return retime(to: offeredDelay)
        case .nudge, .align, .heard, .applySuggestion:
            return []
        }
    }

    /// The subtitle track showing, built in or added from a file.
    var shownSubtitles: MediaTrack.ID? {
        tracks.first { $0.id.kind == .subtitle && $0.isSelected }?.id
    }

    /// The delay the speech suggested for the subtitles showing.
    var suggestion: SubtitleDelay? {
        guard let found = speech.suggestion, found.subtitles == shownSubtitles else { return nil }
        return found.delay
    }

    /// The suggested delay, while it differs enough from the current one to be worth offering.
    var offeredDelay: SubtitleDelay? {
        guard let suggestion, abs(suggestion.duration - subtitleDelay.duration) >= PlayerFeature.suggestionThreshold else { return nil }
        return suggestion
    }

    /// Whether the player hears the speech: while subtitles show, until it suggests a delay for
    /// them, and while the timing strip is open, for its lane.
    var hearsSpeech: Bool {
        shownSubtitles != nil && (speech.lane != nil || suggestion == nil)
    }

    /// The next sample of the speech: often for the open strip's lane, now and then otherwise.
    var nextSpeechSample: Effect {
        .sampleSpeech(speechEvidence, after: speech.lane == nil ? PlayerFeature.speechBackgroundInterval : PlayerFeature.speechSampleInterval)
    }

    private var speechEvidence: Range<Duration> {
        position - PlayerFeature.speechEvidenceBefore ..< position + PlayerFeature.speechEvidenceAfter
    }
}

private func abs(_ duration: Duration) -> Duration {
    duration < .zero ? .zero - duration : duration
}
