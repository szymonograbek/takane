import Foundation
import Testing

struct PreferencesFeatureTests {
    private let english = Language("eng").require()
    private let polish = Language("pol").require()

    private var englishSubtitles: TrackLanguages {
        TrackLanguages(audio: nil, subtitles: PreferredLanguages(primary: english, fallback: nil))
    }

    private var loaded: PreferencesFeature.State {
        PreferencesFeature.State(playback: PlaybackPreferences(languages: englishSubtitles, subtitleStyle: .defaults, seekStep: .ten))
    }

    @Test func editsBeforeThePreferencesLoadAreIgnored() {
        var state = PreferencesFeature.State()
        #expect(PreferencesFeature.reduce(&state, .setAudioLanguages(PreferredLanguages(primary: english, fallback: nil))).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setSubtitleLanguages(nil)).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setSubtitleStyle(.defaults)).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setSeekStep(.thirty)).isEmpty)
    }

    @Test func choosingTheCurrentValueChangesNothing() {
        var state = loaded
        #expect(PreferencesFeature.reduce(&state, .setAudioLanguages(nil)).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setSubtitleLanguages(PreferredLanguages(primary: english, fallback: nil))).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setSubtitleStyle(.defaults)).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setSeekStep(.ten)).isEmpty)
    }

    @Test func eachEditSavesThePreferencesWithIt() {
        var state = loaded
        var bold = SubtitleStyle.defaults
        bold.isBold = true

        let polishAudio = PreferredLanguages(primary: polish, fallback: english)
        #expect(PreferencesFeature.reduce(&state, .setAudioLanguages(polishAudio)) == [
            .update(PlaybackPreferences(
                languages: TrackLanguages(audio: polishAudio, subtitles: PreferredLanguages(primary: english, fallback: nil)),
                subtitleStyle: .defaults,
                seekStep: .ten
            )),
        ])
        #expect(PreferencesFeature.reduce(&state, .setSubtitleLanguages(PreferredLanguages(primary: english, fallback: polish))) == [
            .update(PlaybackPreferences(
                languages: TrackLanguages(audio: nil, subtitles: PreferredLanguages(primary: english, fallback: polish)),
                subtitleStyle: .defaults,
                seekStep: .ten
            )),
        ])
        #expect(PreferencesFeature.reduce(&state, .setSubtitleLanguages(nil)) == [
            .update(PlaybackPreferences(languages: TrackLanguages(audio: nil, subtitles: nil), subtitleStyle: .defaults, seekStep: .ten)),
        ])
        #expect(PreferencesFeature.reduce(&state, .setSubtitleStyle(bold)) == [
            .update(PlaybackPreferences(languages: englishSubtitles, subtitleStyle: bold, seekStep: .ten)),
        ])
        #expect(PreferencesFeature.reduce(&state, .setSeekStep(.thirty)) == [
            .update(PlaybackPreferences(languages: englishSubtitles, subtitleStyle: .defaults, seekStep: .thirty)),
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
        let preferences = loaded.playback.require()
        _ = PreferencesFeature.reduce(&state, .playbackChanged(preferences))
        #expect(state == PreferencesFeature.State(playback: preferences, failure: nil))
    }
}
