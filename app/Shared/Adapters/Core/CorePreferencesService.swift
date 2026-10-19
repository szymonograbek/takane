/// Playback preferences as core's profile settings hold them, in the keys `CorePlaybackSettings`
/// and `CoreSubtitleSettings` read.
struct CorePreferencesService: PreferencesService {
    let runtime: CoreRuntime

    func playback() -> AsyncStream<PlaybackPreferences> {
        runtime.observe(.ctx, as: CtxState.self) { ctx in
            guard case .object(let settings) = ctx.profile.settings else {
                return PlaybackPreferences(languages: .streamDefaults, subtitleStyle: .defaults, seekStep: .defaults)
            }
            return PlaybackPreferences(
                languages: TrackLanguages(
                    audio: CorePlaybackSettings.audioLanguages.read(settings),
                    subtitles: CoreSubtitleSettings.languages(in: settings)
                ),
                subtitleStyle: CoreSubtitleSettings.style(in: settings),
                seekStep: CorePlaybackSettings.seekStep(in: settings)
            )
        }
    }

    func update(_ preferences: PlaybackPreferences) throws(PreferencesError) {
        // core takes the whole settings object, so every other key goes back as it was.
        var settings = try currentSettings()
        CorePlaybackSettings.audioLanguages.write(preferences.languages.audio, into: &settings)
        CorePlaybackSettings.write(preferences.seekStep, into: &settings)
        CoreSubtitleSettings.write(preferences.languages.subtitles, into: &settings)
        CoreSubtitleSettings.write(preferences.subtitleStyle, into: &settings)
        do {
            try runtime.dispatch(.ctx(.updateSettings(.object(settings))))
        } catch {
            throw .rejected(reason: "\(error)")
        }
    }

    private func currentSettings() throws(PreferencesError) -> [String: JSONValue] {
        let profile: Profile
        do {
            profile = try runtime.state(.ctx, as: CtxState.self).profile
        } catch {
            throw .rejected(reason: "\(error)")
        }
        guard case .object(let settings) = profile.settings else { throw .rejected(reason: "settings are not an object") }
        return settings
    }
}
