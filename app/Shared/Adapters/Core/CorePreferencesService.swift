/// The preferences as core's profile settings hold them, in the keys `CoreGeneralSettings`
/// and `CoreSubtitleSettings` read.
struct CorePreferencesService: PreferencesService {
    let runtime: CoreRuntime

    func preferences() -> AsyncStream<Preferences> {
        runtime.observe(.ctx, as: CtxState.self) { ctx in
            guard case .object(let settings) = ctx.profile.settings else {
                return Preferences(languages: .streamDefaults, subtitleStyle: .defaults, seekStep: .defaults, hidesSpoilers: false)
            }
            return Preferences(
                languages: TrackLanguages(
                    audio: CoreGeneralSettings.audioLanguages.read(settings),
                    subtitles: CoreSubtitleSettings.languages(in: settings)
                ),
                subtitleStyle: CoreSubtitleSettings.style(in: settings),
                seekStep: CoreGeneralSettings.seekStep(in: settings),
                hidesSpoilers: CoreGeneralSettings.hidesSpoilers(in: settings)
            )
        }
    }

    func update(_ preferences: Preferences) throws(PreferencesError) {
        // core takes the whole settings object, so every other key goes back as it was.
        var settings = try currentSettings()
        CoreGeneralSettings.audioLanguages.write(preferences.languages.audio, into: &settings)
        CoreGeneralSettings.write(preferences.seekStep, into: &settings)
        CoreGeneralSettings.writeHidesSpoilers(preferences.hidesSpoilers, into: &settings)
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
