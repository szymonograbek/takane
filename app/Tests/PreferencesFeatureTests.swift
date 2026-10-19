import Foundation
import Testing

struct PreferencesFeatureTests {
    private let english = Language("eng").require()
    private let polish = Language("pol").require()

    private var loaded: PreferencesFeature.State {
        PreferencesFeature.State(playback: PlaybackPreferences(
            languages: TrackLanguages(audio: nil, subtitles: .preferred(english, fallback: nil)),
            subtitleStyle: .defaults
        ))
    }

    @Test func editsBeforeThePreferencesLoadAreIgnored() {
        var state = PreferencesFeature.State()
        #expect(PreferencesFeature.reduce(&state, .setAudioLanguage(english)).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setSubtitleLanguages(.off)).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setSubtitleStyle(.defaults)).isEmpty)
    }

    @Test func choosingTheCurrentValueChangesNothing() {
        var state = loaded
        #expect(PreferencesFeature.reduce(&state, .setAudioLanguage(nil)).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setSubtitleLanguages(.preferred(english, fallback: nil))).isEmpty)
        #expect(PreferencesFeature.reduce(&state, .setSubtitleStyle(.defaults)).isEmpty)
    }

    @Test func eachEditSavesThePreferencesWithIt() {
        var state = loaded
        let englishSubtitles = TrackLanguages(audio: nil, subtitles: .preferred(english, fallback: nil))
        var bold = SubtitleStyle.defaults
        bold.isBold = true

        #expect(PreferencesFeature.reduce(&state, .setAudioLanguage(polish)) == [
            .update(PlaybackPreferences(languages: TrackLanguages(audio: polish, subtitles: .preferred(english, fallback: nil)), subtitleStyle: .defaults)),
        ])
        #expect(PreferencesFeature.reduce(&state, .setSubtitleLanguages(.preferred(english, fallback: polish))) == [
            .update(PlaybackPreferences(languages: TrackLanguages(audio: nil, subtitles: .preferred(english, fallback: polish)), subtitleStyle: .defaults)),
        ])
        #expect(PreferencesFeature.reduce(&state, .setSubtitleLanguages(.off)) == [
            .update(PlaybackPreferences(languages: TrackLanguages(audio: nil, subtitles: .off), subtitleStyle: .defaults)),
        ])
        #expect(PreferencesFeature.reduce(&state, .setSubtitleStyle(bold)) == [
            .update(PlaybackPreferences(languages: englishSubtitles, subtitleStyle: bold)),
        ])
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
