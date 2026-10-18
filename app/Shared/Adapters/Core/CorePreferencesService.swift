/// Playback preferences as core's profile settings hold them (`audioLanguage`, `subtitlesLanguage`).
struct CorePreferencesService: PreferencesService {
    let runtime: CoreRuntime

    func playback() -> AsyncStream<PlaybackPreferences> {
        runtime.observe(.ctx, as: CtxState.self) { ctx in
            PlaybackPreferences(languages: TrackLanguages(
                audio: ctx.profile.settings.string("audioLanguage").flatMap(Language.init),
                subtitles: ctx.profile.settings.string("subtitlesLanguage").flatMap(Language.init)
            ))
        }
    }

    func update(_ preferences: PlaybackPreferences) throws(PreferencesError) {
        // core takes the whole settings object, so every other key goes back as it was.
        var settings = try currentSettings()
        settings["audioLanguage"] = preferences.languages.audio.map { .string($0.code) } ?? .null
        settings["subtitlesLanguage"] = preferences.languages.subtitles.map { .string($0.code) } ?? .null
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

private extension JSONValue {
    func string(_ key: String) -> String? {
        guard case .object(let fields) = self, case .string(let value)? = fields[key] else { return nil }
        return value
    }
}
