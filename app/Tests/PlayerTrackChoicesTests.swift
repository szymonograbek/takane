import Foundation
import Testing

struct PlayerTrackChoicesTests {
    private let english = MediaTrack(
        id: MediaTrack.ID(kind: .audio, number: 1), title: nil, language: "eng", codec: "aac",
        channelCount: 2, isForced: false, externalFile: nil, isSelected: true
    )
    private let polish = MediaTrack(
        id: MediaTrack.ID(kind: .audio, number: 2), title: nil, language: "pol", codec: "aac",
        channelCount: 2, isForced: false, externalFile: nil, isSelected: false
    )
    private let subtitles = MediaTrack(
        id: MediaTrack.ID(kind: .subtitle, number: 3), title: nil, language: "eng", codec: "subrip",
        channelCount: nil, isForced: false, externalFile: nil, isSelected: false
    )
    private let synced = AddonSubtitle(
        id: AddonSubtitle.ID(addon: Fixture.manifest, key: Redacted("synced-1")),
        url: Redacted(URL(string: "https://subs.example/synced-1.srt").require()),
        language: "pol",
        label: Redacted("Synced")
    )

    private func opened() -> PlayerFeature.State {
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        return state
    }

    @Test func choosingAudioRemembersEverythingPlayingNow() {
        var state = opened()
        _ = PlayerFeature.reduce(&state, .engine(.tracks([english, polish, subtitles.selected])))
        let remembered = TrackChoices(
            audio: TrackChoices.Track(number: 2, language: "pol"),
            subtitles: .builtIn(TrackChoices.Track(number: 3, language: "eng")),
            speed: .normal
        )
        #expect(PlayerFeature.reduce(&state, .select(polish.id)) == [.select(polish.id), .report(.choices(remembered))])
    }

    @Test func rememberedChoicesApplyOnceTheTracksAreKnown() {
        var state = opened()
        let remembered = TrackChoices(
            audio: TrackChoices.Track(number: 2, language: "pol"),
            subtitles: .builtIn(TrackChoices.Track(number: 3, language: "eng")),
            speed: .oneAndAHalf
        )
        #expect(PlayerFeature.reduce(&state, .remembered(Fixture.candidate(), remembered)).isEmpty)
        #expect(PlayerFeature.reduce(&state, .engine(.tracks([english, polish, subtitles]))) == [
            .select(polish.id), .select(subtitles.id), .setSpeed(.oneAndAHalf),
        ])
        #expect(PlayerFeature.reduce(&state, .engine(.tracks([english, polish, subtitles]))).isEmpty)
    }

    @Test func aRememberedTrackRenumberedInAnotherEpisodeIsFoundByLanguage() {
        var state = opened()
        _ = PlayerFeature.reduce(&state, .engine(.tracks([english, polish])))
        let remembered = TrackChoices(audio: TrackChoices.Track(number: 7, language: "pol"))
        #expect(PlayerFeature.reduce(&state, .remembered(Fixture.candidate(), remembered)) == [.select(polish.id)])
    }

    @Test func aRememberedAddonFileWaitsForItsAddon() {
        var state = opened()
        _ = PlayerFeature.reduce(&state, .engine(.tracks([english])))
        let remembered = TrackChoices(subtitles: .addon(synced.url, language: "pol"))
        #expect(PlayerFeature.reduce(&state, .remembered(Fixture.candidate(), remembered)).isEmpty)
        let loading = SubtitleSource(addon: Fixture.manifest, addonName: Redacted("Subtitle Sync"), subtitles: .loading)
        #expect(PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), [loading])).isEmpty)
        let loaded = SubtitleSource(addon: Fixture.manifest, addonName: Redacted("Subtitle Sync"), subtitles: .loaded([synced]))
        #expect(PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), [loaded])) == [.addSubtitles(synced)])
        #expect(state.session?.restore == .settled)
    }

    @Test func theViewersChoiceOutranksWhatArrivesLater() {
        var state = opened()
        _ = PlayerFeature.reduce(&state, .engine(.tracks([english, polish])))
        _ = PlayerFeature.reduce(&state, .setSpeed(.double))
        let remembered = TrackChoices(audio: TrackChoices.Track(number: 2, language: "pol"), speed: .half)
        #expect(PlayerFeature.reduce(&state, .remembered(Fixture.candidate(), remembered)).isEmpty)
        #expect(PlayerFeature.reduce(&state, .engine(.tracks([english, polish]))).isEmpty)
    }

    @Test func theViewersChoiceCancelsAnAddonFileStillWaiting() {
        var state = opened()
        _ = PlayerFeature.reduce(&state, .engine(.tracks([english, subtitles])))
        _ = PlayerFeature.reduce(&state, .remembered(Fixture.candidate(), TrackChoices(subtitles: .addon(synced.url, language: "pol"))))
        _ = PlayerFeature.reduce(&state, .chooseSubtitles(.builtIn(subtitles.id)))
        let loaded = SubtitleSource(addon: Fixture.manifest, addonName: Redacted("Subtitle Sync"), subtitles: .loaded([synced]))
        #expect(PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), [loaded])).isEmpty)
    }

    @Test func withNothingRememberedTheTracksStayAsTheyStarted() {
        var state = opened()
        #expect(PlayerFeature.reduce(&state, .engine(.tracks([english, polish, subtitles]))).isEmpty)
        #expect(state.session?.restore == .awaiting)
    }

    @Test func choicesRememberedForAnotherCandidateAreDropped() {
        var state = opened()
        _ = PlayerFeature.reduce(&state, .engine(.tracks([english, polish])))
        let remembered = TrackChoices(audio: TrackChoices.Track(number: 2, language: "pol"))
        #expect(PlayerFeature.reduce(&state, .remembered(Fixture.candidate(index: 1), remembered)).isEmpty)
        #expect(state.session?.restore == .awaiting)
    }
}
