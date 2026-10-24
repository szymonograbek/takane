import Foundation
import Testing

struct PlayerSubtitleTimingTests {
    private let english = MediaTrack(
        id: MediaTrack.ID(kind: .subtitle, number: 3), title: nil, language: "eng", codec: "subrip",
        channelCount: nil, isForced: false, externalFile: nil, isSelected: true
    )
    private let polish = MediaTrack(
        id: MediaTrack.ID(kind: .subtitle, number: 4), title: nil, language: "pol", codec: "subrip",
        channelCount: nil, isForced: false, externalFile: nil, isSelected: false
    )
    private let synced = AddonSubtitle(
        id: AddonSubtitle.ID(addon: Fixture.manifest, key: Redacted("synced-1")),
        url: Redacted(URL(string: "https://subs.example/synced-1.srt").require()),
        source: PlaybackSource(url: Redacted(URL(string: "https://subs.example/synced-1.srt").require()), headers: [:]),
        language: "pol",
        label: Redacted("Synced")
    )

    private func delay(_ milliseconds: Int64) -> SubtitleDelay {
        SubtitleDelay(clamping: .milliseconds(milliseconds))
    }

    private func cue(_ number: Int, at start: Duration) -> TimedCue {
        TimedCue(id: TimedCue.ID(number: number), range: start ..< start + .seconds(2), text: Redacted("Line \(number)"))
    }

    /// Playing with English subtitles on.
    private func playing(_ tracks: [MediaTrack]? = nil) -> PlayerFeature.State {
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        _ = PlayerFeature.reduce(&state, .engine(.tracks(tracks ?? [english, polish])))
        return state
    }

    private func remembered(_ delay: SubtitleDelay) -> PlayerFeature.Effect {
        .report(.choices(TrackChoices(subtitles: .builtIn(TrackChoices.Track(number: 3, language: "eng")), speed: .normal, subtitleDelay: delay)))
    }

    @Test func eachNudgeMovesTheSubtitlesAtOnceAndIsRemembered() {
        var state = playing()
        _ = PlayerFeature.reduce(&state, .subtitleTiming(.nudge(.forward, .fine)))
        _ = PlayerFeature.reduce(&state, .subtitleTiming(.nudge(.forward, .fine)))
        #expect(PlayerFeature.reduce(&state, .subtitleTiming(.nudge(.forward, .fine))) == [.setSubtitleDelay(delay(300)), remembered(delay(300))])
        #expect(PlayerFeature.reduce(&state, .subtitleTiming(.nudge(.backward, .coarse))) == [.setSubtitleDelay(delay(-200)), remembered(delay(-200))])
        #expect(state.session?.subtitleDelay == delay(-200))
    }

    @Test func theDelayStopsThirtySecondsEitherWay() {
        var state = playing()
        for _ in 0..<61 {
            _ = PlayerFeature.reduce(&state, .subtitleTiming(.nudge(.forward, .coarse)))
        }
        #expect(state.session?.subtitleDelay == delay(30_000))
        #expect(PlayerFeature.reduce(&state, .subtitleTiming(.nudge(.forward, .fine))).isEmpty)
    }

    @Test func withSubtitlesOffThereIsNothingToTime() {
        var state = playing([english.unselected])
        #expect(PlayerFeature.reduce(&state, .subtitleTiming(.nudge(.forward, .fine))).isEmpty)
        _ = PlayerFeature.reduce(&state, .engine(.cueTimeline([cue(1, at: .seconds(61))])))
        _ = PlayerFeature.reduce(&state, .engine(.position(.seconds(60))))
        #expect(PlayerFeature.reduce(&state, .subtitleTiming(.align)).isEmpty)
        #expect(state.session?.subtitleDelay == .zero)
    }

    @Test func thisLineStartsNowMovesTheNearestLineToThePlayhead() {
        var state = playing()
        _ = PlayerFeature.reduce(&state, .engine(.cueTimeline([cue(1, at: .seconds(55)), cue(2, at: .milliseconds(61_340))])))
        _ = PlayerFeature.reduce(&state, .engine(.position(.seconds(60))))
        #expect(PlayerFeature.reduce(&state, .subtitleTiming(.align)) == [.setSubtitleDelay(delay(-1_300)), remembered(delay(-1_300))])
    }

    @Test func thisLineStartsNowWithNoLineNearbyDoesNothing() {
        var state = playing()
        _ = PlayerFeature.reduce(&state, .engine(.cueTimeline([cue(1, at: .seconds(75))])))
        _ = PlayerFeature.reduce(&state, .engine(.position(.seconds(60))))
        #expect(PlayerFeature.reduce(&state, .subtitleTiming(.align)).isEmpty)
    }

    @Test func theLineIsPickedWhereTheCurrentDelayShowsIt() {
        let cues = [cue(1, at: .seconds(48)), cue(2, at: .seconds(58))]
        #expect(PlayerFeature.alignmentTarget(cues, at: .seconds(60), from: delay(11_000)) == cues[0])
        #expect(PlayerFeature.alignmentTarget(cues, at: .seconds(60), from: .zero) == cues[1])
        #expect(PlayerFeature.alignmentTarget(cues, at: .seconds(80), from: .zero) == nil)
        #expect(PlayerFeature.alignmentTarget([], at: .seconds(60), from: .zero) == nil)
        #expect(PlayerFeature.delay(starting: cues[0], at: .milliseconds(60_040)) == delay(12_000))
    }

    @Test func resettingPutsTheSubtitlesBackInSync() {
        var state = playing()
        _ = PlayerFeature.reduce(&state, .subtitleTiming(.nudge(.backward, .coarse)))
        #expect(PlayerFeature.reduce(&state, .subtitleTiming(.reset)) == [.setSubtitleDelay(.zero), remembered(.zero)])
        #expect(PlayerFeature.reduce(&state, .subtitleTiming(.reset)).isEmpty)
    }

    @Test func otherSubtitlesStartInSync() {
        var state = playing()
        _ = PlayerFeature.reduce(&state, .subtitleTiming(.nudge(.forward, .coarse)))
        let choices = TrackChoices(subtitles: .builtIn(TrackChoices.Track(number: 4, language: "pol")), speed: .normal)
        #expect(PlayerFeature.reduce(&state, .chooseSubtitles(.builtIn(polish.id))) == [
            .select(polish.id), .setSubtitleDelay(.zero), .report(.choices(choices)),
        ])
        #expect(state.session?.subtitleDelay == .zero)
    }

    @Test func anotherTrackPickedByNumberStartsInSync() {
        var state = playing()
        _ = PlayerFeature.reduce(&state, .subtitleTiming(.nudge(.forward, .coarse)))
        let choices = TrackChoices(subtitles: .builtIn(TrackChoices.Track(number: 4, language: "pol")), speed: .normal)
        #expect(PlayerFeature.reduce(&state, .select(polish.id)) == [.select(polish.id), .setSubtitleDelay(.zero), .report(.choices(choices))])
        #expect(state.session?.subtitleDelay == .zero)
    }

    @Test func choosingTheSubtitlesShowingKeepsTheirTiming() {
        var state = playing()
        _ = PlayerFeature.reduce(&state, .subtitleTiming(.nudge(.forward, .coarse)))
        #expect(PlayerFeature.reduce(&state, .chooseSubtitles(.builtIn(english.id))).isEmpty)
        #expect(state.session?.subtitleDelay == delay(500))
    }

    @Test func aRememberedDelayComesBackWithItsSubtitles() {
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        let saved = TrackChoices(subtitles: .builtIn(TrackChoices.Track(number: 4, language: "pol")), subtitleDelay: delay(800))
        _ = PlayerFeature.reduce(&state, .remembered(Fixture.candidate(), saved))
        #expect(PlayerFeature.reduce(&state, .engine(.tracks([english, polish]))) == [.select(polish.id), .setSubtitleDelay(delay(800))])
    }

    @Test func aRememberedDelayWaitsForItsAddonFile() {
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        _ = PlayerFeature.reduce(&state, .engine(.tracks([english.unselected])))
        let saved = TrackChoices(subtitles: .addon(synced.url, language: "pol"), subtitleDelay: delay(-1_500))
        #expect(PlayerFeature.reduce(&state, .remembered(Fixture.candidate(), saved)).isEmpty)
        let loaded = SubtitleSource(addon: Fixture.manifest, addonName: Redacted("Subtitle Sync"), subtitles: .loaded([synced]))
        #expect(PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), [loaded])) == [
            .addSubtitles(synced), .setSubtitleDelay(delay(-1_500)),
        ])
    }

    @Test func aRememberedDelayWithoutItsSubtitlesStaysUnused() {
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        let saved = TrackChoices(subtitles: .builtIn(TrackChoices.Track(number: 9, language: "jpn")), subtitleDelay: delay(800))
        _ = PlayerFeature.reduce(&state, .remembered(Fixture.candidate(), saved))
        #expect(PlayerFeature.reduce(&state, .engine(.tracks([english, polish]))).isEmpty)
        #expect(state.session?.subtitleDelay == .zero)
    }

    @Test func timedSubtitlesAreNoLongerSwappedForAnotherPick() {
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        let polishFirst = PreferredLanguages(primary: Language("pol").require(), fallback: nil)
        let preferences = Fixture.preferences(languages: TrackLanguages(audio: nil, subtitles: polishFirst))
        _ = PlayerFeature.reduce(&state, .preferencesRead(Fixture.candidate(), preferences))
        let picked = MediaTrack(
            id: MediaTrack.ID(kind: .subtitle, number: 9), title: nil, language: "pol", codec: "subrip",
            channelCount: nil, isForced: false, externalFile: synced.url, isSelected: true
        )
        let first = SubtitleSource(addon: Fixture.manifest, addonName: Redacted("Add-on"), subtitles: .loaded([synced]))
        _ = PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), [first]))
        _ = PlayerFeature.reduce(&state, .engine(.tracks([picked])))
        _ = PlayerFeature.reduce(&state, .subtitleTiming(.nudge(.forward, .fine)))
        let better = AddonSubtitle(
            id: AddonSubtitle.ID(addon: Fixture.manifest, key: Redacted("better")),
            url: Redacted(URL(string: "https://subs.example/better.srt").require()),
            source: PlaybackSource(url: Redacted(URL(string: "https://subs.example/better.srt").require()), headers: [:]),
            language: "pol",
            label: nil
        )
        let answer = SubtitleSource(addon: Fixture.manifest, addonName: Redacted("Add-on"), subtitles: .loaded([better, synced]))
        #expect(PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), [answer])).isEmpty)
    }

    @Test func theCueTimelineFollowsTheEngine() {
        var state = playing()
        let cues = [cue(1, at: .seconds(10)), cue(2, at: .seconds(14))]
        #expect(PlayerFeature.reduce(&state, .engine(.cueTimeline(cues))).isEmpty)
        #expect(state.session?.cueTimeline == cues)
    }
}
