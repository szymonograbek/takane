import Foundation

/// The preferences as core's profile settings hold them, in the keys `CoreGeneralSettings`
/// and `CoreSubtitleSettings` read, with `CoreDeviceSettings` laid over them from this device.
struct CorePreferencesService: PreferencesService {
    let runtime: CoreRuntime

    func preferences() -> AsyncStream<Preferences> {
        runtime.observe(.ctx, as: CtxState.self) { ctx in
            var preferences = Self.preferences(in: ctx.profile.settings)
            CoreDeviceSettings.read(into: &preferences, from: .standard, for: ctx.profile)
            return preferences
        }
    }

    func update(_ preferences: Preferences) throws(PreferencesError) {
        let profile = try currentProfile()
        // core takes the whole settings object, so every other key goes back as it was.
        guard case .object(var settings) = profile.settings else { throw .rejected(reason: "settings are not an object") }
        CoreGeneralSettings.audioLanguages.write(preferences.languages.audio, into: &settings)
        CoreGeneralSettings.write(preferences.seekStep, into: &settings)
        CoreGeneralSettings.writeHidesSpoilers(preferences.hidesSpoilers, into: &settings)
        CoreGeneralSettings.write(preferences.upNext, into: &settings)
        CoreSubtitleSettings.write(preferences.languages.subtitles, into: &settings)
        CoreSubtitleSettings.write(preferences.subtitleStyle, into: &settings)
        do {
            try runtime.dispatch(.ctx(.updateSettings(.object(settings))))
        } catch {
            throw .rejected(reason: "\(error)")
        }
        CoreDeviceSettings.write(preferences, into: .standard, for: profile)
        // core does not report a change it does not hold, so the stream rereads for the device settings.
        runtime.refresh(.ctx)
    }

    /// `skipSegmentSource` is a placeholder until `CoreDeviceSettings` reads it.
    private static func preferences(in settings: JSONValue) -> Preferences {
        guard case .object(let settings) = settings else {
            return Preferences(
                languages: .streamDefaults, subtitleStyle: .defaults, seekStep: .defaults, hidesSpoilers: false, upNext: .defaults,
                skipSegmentSource: .defaults
            )
        }
        return Preferences(
            languages: TrackLanguages(
                audio: CoreGeneralSettings.audioLanguages.read(settings),
                subtitles: CoreSubtitleSettings.languages(in: settings)
            ),
            subtitleStyle: CoreSubtitleSettings.style(in: settings),
            seekStep: CoreGeneralSettings.seekStep(in: settings),
            hidesSpoilers: CoreGeneralSettings.hidesSpoilers(in: settings),
            upNext: CoreGeneralSettings.upNext(in: settings),
            skipSegmentSource: .defaults
        )
    }

    private func currentProfile() throws(PreferencesError) -> Profile {
        do {
            return try runtime.state(.ctx, as: CtxState.self).profile
        } catch {
            throw .rejected(reason: "\(error)")
        }
    }
}
