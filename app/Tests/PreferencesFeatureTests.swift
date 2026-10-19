import Foundation
import Testing

struct PreferencesFeatureTests {
    private let english = Language("eng").require()
    private let polish = Language("pol").require()

    private var englishSubtitles: TrackLanguages {
        TrackLanguages(audio: nil, subtitles: PreferredLanguages(primary: english, fallback: nil))
    }

    private var loaded: PreferencesFeature.State {
        PreferencesFeature.State(
            preferences: Preferences(languages: englishSubtitles, subtitleStyle: .defaults, seekStep: .ten, hidesSpoilers: false, upNext: .defaults)
        )
    }

    @Test func editsBeforeThePreferencesLoadAreIgnored() {
        var state = PreferencesFeature.State()
        #expect(PreferencesFeature.reduce(&state, .setAudioLanguages(PreferredLanguages(primary: english, fallback: nil))).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setSubtitleLanguages(nil)).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setSubtitleStyle(.defaults)).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setSeekStep(.thirty)).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setHidesSpoilers(true)).isEmpty)
    }

    @Test func choosingTheCurrentValueChangesNothing() {
        var state = loaded
        #expect(PreferencesFeature.reduce(&state, .setAudioLanguages(nil)).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setSubtitleLanguages(PreferredLanguages(primary: english, fallback: nil))).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setSubtitleStyle(.defaults)).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setSeekStep(.ten)).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setHidesSpoilers(false)).isEmpty)
    }

    @Test func eachEditSavesThePreferencesWithIt() {
        var state = loaded
        var bold = SubtitleStyle.defaults
        bold.isBold = true

        let polishAudio = PreferredLanguages(primary: polish, fallback: english)
        #expect(PreferencesFeature.reduce(&state, .setAudioLanguages(polishAudio)) == [
            .update(Preferences(
                languages: TrackLanguages(audio: polishAudio, subtitles: PreferredLanguages(primary: english, fallback: nil)),
                subtitleStyle: .defaults,
                seekStep: .ten,
                hidesSpoilers: false,
                upNext: .defaults
            )),
        ])
        #expect(PreferencesFeature.reduce(&state, .setSubtitleLanguages(PreferredLanguages(primary: english, fallback: polish))) == [
            .update(Preferences(
                languages: TrackLanguages(audio: nil, subtitles: PreferredLanguages(primary: english, fallback: polish)),
                subtitleStyle: .defaults,
                seekStep: .ten,
                hidesSpoilers: false,
                upNext: .defaults
            )),
        ])
        #expect(PreferencesFeature.reduce(&state, .setSubtitleLanguages(nil)) == [
            .update(Preferences(
                languages: TrackLanguages(audio: nil, subtitles: nil), subtitleStyle: .defaults, seekStep: .ten, hidesSpoilers: false, upNext: .defaults
            )),
        ])
        #expect(PreferencesFeature.reduce(&state, .setSubtitleStyle(bold)) == [
            .update(Preferences(languages: englishSubtitles, subtitleStyle: bold, seekStep: .ten, hidesSpoilers: false, upNext: .defaults)),
        ])
        #expect(PreferencesFeature.reduce(&state, .setSeekStep(.thirty)) == [
            .update(Preferences(languages: englishSubtitles, subtitleStyle: .defaults, seekStep: .thirty, hidesSpoilers: false, upNext: .defaults)),
        ])
        #expect(PreferencesFeature.reduce(&state, .setHidesSpoilers(true)) == [
            .update(Preferences(languages: englishSubtitles, subtitleStyle: .defaults, seekStep: .ten, hidesSpoilers: true, upNext: .defaults)),
        ])
        let off = UpNextBehavior(notice: .off, autoplay: true)
        #expect(PreferencesFeature.reduce(&state, .setUpNextNotice(.off)) == [
            .update(Preferences(languages: englishSubtitles, subtitleStyle: .defaults, seekStep: .ten, hidesSpoilers: false, upNext: off)),
        ])
        let manual = UpNextBehavior(notice: .thirtyFiveSeconds, autoplay: false)
        #expect(PreferencesFeature.reduce(&state, .setAutoplaysNext(false)) == [
            .update(Preferences(languages: englishSubtitles, subtitleStyle: .defaults, seekStep: .ten, hidesSpoilers: false, upNext: manual)),
        ])
    }

    @Test func languagesInPreferenceOrderStartWithThePrimary() {
        #expect(PreferredLanguages(primary: english, fallback: polish).inPreferenceOrder == [english, polish])
        #expect(PreferredLanguages(primary: english, fallback: nil).inPreferenceOrder == [english])
    }

    @Test func aFailedSaveShowsUntilThePreferencesChange() {
        var state = loaded
        _ = PreferencesFeature.reduce(&state, .updateFailed(.rejected(reason: "offline")))
        #expect(state.failure == .rejected(reason: "offline"))
        let preferences = loaded.preferences.require()
        _ = PreferencesFeature.reduce(&state, .changed(preferences))
        #expect(state == PreferencesFeature.State(preferences: preferences, failure: nil))
    }
}
