import Foundation
import Testing

struct PlayerSecondSubtitlesTests {
    private let english = MediaTrack(
        id: MediaTrack.ID(kind: .subtitle, number: 3), title: nil, language: "eng", codec: "subrip",
        channelCount: nil, isForced: false, externalFile: nil, isSelected: true
    )
    private let polish = MediaTrack(
        id: MediaTrack.ID(kind: .subtitle, number: 4), title: nil, language: "pol", codec: "subrip",
        channelCount: nil, isForced: false, externalFile: nil, isSelected: false
    )
    private let pictures = MediaTrack(
        id: MediaTrack.ID(kind: .subtitle, number: 5), title: nil, language: "ger", codec: "hdmv_pgs_subtitle",
        channelCount: nil, isForced: false, externalFile: nil, isSelected: false, isImageBased: true
    )
    private let spanish = AddonSubtitle(
        id: AddonSubtitle.ID(addon: Fixture.manifest, key: Redacted("es-1")),
        url: Redacted(URL(string: "https://subs.example/es-1.srt").require()),
        source: PlaybackSource(url: Redacted(URL(string: "https://subs.example/es-1.srt").require()), headers: [:]),
        language: "spa",
        label: nil
    )

    private func playing(_ tracks: [MediaTrack]) -> PlayerFeature.State {
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        _ = PlayerFeature.reduce(&state, .engine(.tracks(tracks)))
        return state
    }

    @Test func aTrackOfTheStreamShowsSecondWithoutBeingRemembered() {
        var state = playing([english, polish])
        #expect(PlayerFeature.reduce(&state, .chooseSubtitles(.builtIn(polish.id), for: .second)) == [.selectSecond(polish.id)])
        #expect(state.session?.secondSubtitleChoice == .builtIn(polish.id))
        #expect(state.session?.subtitleChoice == .builtIn(english.id))
    }

    @Test func anAddonFileIsAddedOnceAndThenShownFromItsTrack() {
        var state = playing([english])
        let found = SubtitleSource(addon: Fixture.manifest, addonName: Redacted("Subtitles"), subtitles: .loaded([spanish]))
        _ = PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), [found]))
        #expect(PlayerFeature.reduce(&state, .chooseSubtitles(.addon(spanish.id), for: .second)) == [.addSecondSubtitles(spanish)])
        let added = MediaTrack(
            id: MediaTrack.ID(kind: .subtitle, number: 9), title: nil, language: "spa", codec: "subrip",
            channelCount: nil, isForced: false, externalFile: spanish.url, isSelected: false
        )
        #expect(PlayerFeature.reduce(&state, .engine(.tracks([english, added]))).isEmpty)
        #expect(PlayerFeature.reduce(&state, .chooseSubtitles(.off, for: .second)) == [.turnOffSecondSubtitles])
        #expect(PlayerFeature.reduce(&state, .chooseSubtitles(.addon(spanish.id), for: .second)) == [.selectSecond(added.id)])
    }

    @Test func theFirstSubtitlesAndPictureTracksCannotShowSecond() {
        var state = playing([english, polish, pictures])
        #expect(PlayerFeature.reduce(&state, .chooseSubtitles(.builtIn(english.id), for: .second)).isEmpty)
        #expect(PlayerFeature.reduce(&state, .chooseSubtitles(.builtIn(pictures.id), for: .second)).isEmpty)
        #expect(state.session?.secondSubtitleChoice == .off)
        #expect(state.session?.secondSubtitleTracks == [english, polish])
    }

    @Test func choosingTheSecondAsTheFirstTurnsTheSecondOff() {
        var state = playing([english, polish])
        _ = PlayerFeature.reduce(&state, .chooseSubtitles(.builtIn(polish.id), for: .second))
        #expect(PlayerFeature.reduce(&state, .chooseSubtitles(.builtIn(polish.id))) == [
            .select(polish.id), .report(.choices(TrackChoices(subtitles: .builtIn(TrackChoices.Track(number: 4, language: "pol")), speed: .normal))),
        ])
        #expect(PlayerFeature.reduce(&state, .engine(.tracks([english.unselected, polish.selected]))) == [.turnOffSecondSubtitles])
        #expect(state.session?.secondSubtitleChoice == .off)
    }

    @Test func timingMovesTheFirstSubtitlesOnly() {
        var state = playing([english, polish])
        _ = PlayerFeature.reduce(&state, .chooseSubtitles(.builtIn(polish.id), for: .second))
        let effects = PlayerFeature.reduce(&state, .subtitleTiming(.nudge(.forward, .fine)))
        #expect(effects.first == .setSubtitleDelay(SubtitleDelay(clamping: .milliseconds(100))))
        #expect(!effects.contains(.turnOffSecondSubtitles))
        #expect(state.session?.secondSubtitleChoice == .builtIn(polish.id))
    }

    @Test func aNewStreamStartsWithoutSecondSubtitles() {
        var state = playing([english, polish])
        _ = PlayerFeature.reduce(&state, .chooseSubtitles(.builtIn(polish.id), for: .second))
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        #expect(state.session?.secondSubtitleChoice == .off)
    }
}
