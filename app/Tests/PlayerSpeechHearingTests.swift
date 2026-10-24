import Foundation
import Testing

extension Fixture {
    /// What the player sends when subtitles first show at the start: it starts hearing speech and
    /// samples it now and then for a suggested delay.
    static let startsHearing: [PlayerFeature.Effect] = [
        .hearSpeech(true), .sampleSpeech(.seconds(-180) ..< .seconds(15), after: .seconds(5)),
    ]
}

/// When the player hears speech: while subtitles show, until it suggests a delay for them, and while
/// the timing strip is open.
struct PlayerSpeechHearingTests {
    private func subtitles(_ number: Int, _ language: String, selected: Bool) -> MediaTrack {
        MediaTrack(
            id: MediaTrack.ID(kind: .subtitle, number: number), title: nil, language: language, codec: "subrip",
            channelCount: nil, isForced: false, externalFile: nil, isSelected: selected
        )
    }

    /// Lines every few seconds, and speech that starts 1.4 s after each.
    private var dialogue: (cues: [TimedCue], speech: SpeechActivity) {
        let gaps = [3, 7, 4, 9, 5, 2, 8, 6, 3, 10, 4, 7, 5, 9, 3]
        let starts = gaps.reduce(into: [5]) { starts, gap in starts.append((starts.last ?? 0) + 2 + gap) }
        let cues = starts.enumerated().map { index, start in
            TimedCue(id: TimedCue.ID(number: index), range: .seconds(start) ..< .seconds(start + 2), text: Redacted("Line \(index)"))
        }
        let frames = (0..<1_200).map { frame -> SpeechActivity.Frame in
            let time = SpeechActivity.frameDuration * frame - .milliseconds(1_400)
            return cues.contains { $0.range.contains(time) } ? .speech : .quiet
        }
        return (cues, SpeechActivity(firstFrame: 0, frames: frames))
    }

    private func opened(with tracks: [MediaTrack]) -> (PlayerFeature.State, [PlayerFeature.Effect]) {
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        _ = PlayerFeature.reduce(&state, .loadStarted(Fixture.candidate(), Fixture.load))
        let effects = PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks(tracks)))
        return (state, effects)
    }

    @Test func showingSubtitlesStartsHearingAndTurningThemOffStops() {
        var (state, shown) = opened(with: [subtitles(3, "eng", selected: true)])
        #expect(Array(shown.suffix(2)) == Fixture.startsHearing)
        _ = PlayerFeature.reduce(&state, .chooseSubtitles(.off))
        #expect(PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([subtitles(3, "eng", selected: false)]))) == [.hearSpeech(false)])
        #expect(PlayerFeature.reduce(&state, .subtitleTiming(.heard(.empty))).isEmpty)
    }

    @Test func noSubtitlesHearNothing() {
        let (state, effects) = opened(with: [subtitles(3, "eng", selected: false)])
        #expect(!effects.contains(.hearSpeech(true)))
        #expect(state.session?.hearsSpeech == false)
    }

    @Test func hearingStopsOnceASuggestionIsFoundAndTheStripHearsAgain() {
        var (state, _) = opened(with: [subtitles(3, "eng", selected: true)])
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .cueTimeline(dialogue.cues)))
        #expect(PlayerFeature.reduce(&state, .subtitleTiming(.heard(dialogue.speech))) == [.hearSpeech(false)])
        #expect(state.session?.suggestion == SubtitleDelay(clamping: .milliseconds(1_400)))
        #expect(PlayerFeature.reduce(&state, .subtitleTiming(.listen)) == [.sampleSpeech(.seconds(-180) ..< .seconds(15), after: .zero), .hearSpeech(true)])
        #expect(state.session?.offeredDelay == SubtitleDelay(clamping: .milliseconds(1_400)))
        #expect(PlayerFeature.reduce(&state, .subtitleTiming(.stopListening)) == [.hearSpeech(false)])
    }

    @Test func anotherSubtitleFileIsHeardAfresh() {
        var (state, _) = opened(with: [subtitles(3, "eng", selected: true), subtitles(4, "pol", selected: false)])
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .cueTimeline(dialogue.cues)))
        _ = PlayerFeature.reduce(&state, .subtitleTiming(.heard(dialogue.speech)))
        let switched = [subtitles(3, "eng", selected: false), subtitles(4, "pol", selected: true)]
        #expect(PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks(switched))) == Fixture.startsHearing)
        #expect(state.session?.suggestion == nil)
    }
}
