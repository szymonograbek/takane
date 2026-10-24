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
        source: PlaybackSource(url: Redacted(URL(string: "https://subs.example/synced-1.srt").require()), headers: [:]),
        language: "pol",
        label: Redacted("Synced")
    )

    private func opened() -> PlayerFeature.State {
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        _ = PlayerFeature.reduce(&state, .loadStarted(Fixture.candidate(), Fixture.load))
        return state
    }

    @Test func choosingAudioRemembersEverythingPlayingNow() {
        var state = opened()
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english, polish, subtitles.selected])))
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
        #expect(PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english, polish, subtitles]))) == [
            .select(polish.id), .select(subtitles.id), .setSpeed(.oneAndAHalf),
        ])
        #expect(PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english, polish, subtitles]))).isEmpty)
    }

    @Test func aRememberedTrackRenumberedInAnotherEpisodeIsFoundByLanguage() {
        var state = opened()
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english, polish])))
        let remembered = TrackChoices(audio: TrackChoices.Track(number: 7, language: "pol"))
        #expect(PlayerFeature.reduce(&state, .remembered(Fixture.candidate(), remembered)) == [.select(polish.id)])
    }

    @Test func aRememberedAddonFileWaitsForItsAddon() {
        var state = opened()
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english])))
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
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english, polish])))
        _ = PlayerFeature.reduce(&state, .setSpeed(.double))
        let remembered = TrackChoices(audio: TrackChoices.Track(number: 2, language: "pol"), speed: .half)
        #expect(PlayerFeature.reduce(&state, .remembered(Fixture.candidate(), remembered)).isEmpty)
        #expect(PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english, polish]))).isEmpty)
    }

    @Test func theViewersChoiceCancelsAnAddonFileStillWaiting() {
        var state = opened()
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english, subtitles])))
        _ = PlayerFeature.reduce(&state, .remembered(Fixture.candidate(), TrackChoices(subtitles: .addon(synced.url, language: "pol"))))
        _ = PlayerFeature.reduce(&state, .chooseSubtitles(.builtIn(subtitles.id)))
        let loaded = SubtitleSource(addon: Fixture.manifest, addonName: Redacted("Subtitle Sync"), subtitles: .loaded([synced]))
        #expect(PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), [loaded])).isEmpty)
    }

    @Test func withNothingRememberedTheTracksStayAsTheyStarted() {
        var state = opened()
        #expect(PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english, polish, subtitles]))).isEmpty)
        #expect(state.session?.restore == .awaiting)
    }

    @Test func choicesRememberedForAnotherCandidateAreDropped() {
        var state = opened()
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english, polish])))
        let remembered = TrackChoices(audio: TrackChoices.Track(number: 2, language: "pol"))
        #expect(PlayerFeature.reduce(&state, .remembered(Fixture.candidate(index: 1), remembered)).isEmpty)
        #expect(state.session?.restore == .awaiting)
    }

    private let polishFirst = PreferredLanguages(primary: Language("pol").require(), fallback: Language("eng").require())

    private func openedPreferringPolish() -> PlayerFeature.State {
        var state = opened()
        let preferences = Fixture.preferences(languages: TrackLanguages(audio: nil, subtitles: polishFirst))
        _ = PlayerFeature.reduce(&state, .preferencesRead(Fixture.candidate(), preferences))
        return state
    }

    private func source(_ addon: ManifestURL, _ subtitles: Remote<[AddonSubtitle], SubtitleSourceError>) -> SubtitleSource {
        SubtitleSource(addon: addon, addonName: Redacted("Add-on"), subtitles: subtitles)
    }

    private func file(_ key: String, language: String, addon: ManifestURL = Fixture.manifest) -> AddonSubtitle {
        let url = Redacted(URL(string: "https://subs.example/\(key).srt").require())
        return AddonSubtitle(
            id: AddonSubtitle.ID(addon: addon, key: Redacted(key)),
            url: url,
            source: PlaybackSource(url: url, headers: [:]),
            language: language,
            label: nil
        )
    }

    @Test func theFirstAddonFileInThePreferredLanguageShowsWhenTheStreamHasNone() {
        var state = openedPreferringPolish()
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english, subtitles])))
        let found = [source(Fixture.manifest, .loaded([file("en", language: "eng"), synced, file("pl-2", language: "pol")]))]
        #expect(PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), found)) == [.addSubtitles(synced)])
    }

    @Test func aTrackOfTheStreamInThePreferredLanguageStays() {
        var state = openedPreferringPolish()
        let polishTrack = MediaTrack(
            id: MediaTrack.ID(kind: .subtitle, number: 4), title: nil, language: "pol", codec: "subrip",
            channelCount: nil, isForced: false, externalFile: nil, isSelected: true
        )
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english, polishTrack])))
        #expect(PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), [source(Fixture.manifest, .loaded([synced]))])).isEmpty)
    }

    @Test func aFallbackFileWaitsUntilNoAddonOffersThePreferredLanguage() {
        var state = openedPreferringPolish()
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english])))
        let englishFile = file("en", language: "eng", addon: Fixture.otherManifest)
        let answering = [source(Fixture.manifest, .loading), source(Fixture.otherManifest, .loaded([englishFile]))]
        #expect(PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), answering)).isEmpty)
        let answered = [source(Fixture.manifest, .loaded([])), source(Fixture.otherManifest, .loaded([englishFile]))]
        #expect(PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), answered)) == [.addSubtitles(englishFile)])
    }

    @Test func aLaterAnswerReplacesThePick() {
        var state = openedPreferringPolish()
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english])))
        let untimed = file("pl-untimed", language: "pol")
        _ = PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), [source(Fixture.manifest, .loaded([untimed]))]))
        let added = MediaTrack(
            id: MediaTrack.ID(kind: .subtitle, number: 9), title: nil, language: "pol", codec: "subrip",
            channelCount: nil, isForced: false, externalFile: untimed.url, isSelected: true
        )
        #expect(PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english, added]))) == Fixture.startsHearing)
        #expect(PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), [source(Fixture.manifest, .loading)])).isEmpty)
        let timed = [source(Fixture.manifest, .loaded([synced, untimed]))]
        #expect(PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), timed)) == [.addSubtitles(synced)])
    }

    @Test func theViewersChoiceStopsThePicking() {
        var state = openedPreferringPolish()
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english, subtitles])))
        _ = PlayerFeature.reduce(&state, .chooseSubtitles(.builtIn(subtitles.id)))
        #expect(PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), [source(Fixture.manifest, .loaded([synced]))])).isEmpty)
    }

    @Test func rememberedSubtitlesOutrankThePick() {
        var state = openedPreferringPolish()
        let remembered = TrackChoices(subtitles: .builtIn(TrackChoices.Track(number: 3, language: "eng")))
        _ = PlayerFeature.reduce(&state, .remembered(Fixture.candidate(), remembered))
        #expect(PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english, subtitles]))) == [.select(subtitles.id)])
        #expect(PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), [source(Fixture.manifest, .loaded([synced]))])).isEmpty)
    }

    @Test func withoutSubtitleLanguagesNothingIsPicked() {
        var state = opened()
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .tracks([english])))
        #expect(PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), [source(Fixture.manifest, .loaded([synced]))])).isEmpty)
    }
}
