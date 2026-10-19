/// Playback preferences apart from subtitles as core's profile settings hold them:
/// `audioLanguage` and `secondaryAudioLanguage`, and `seekTimeDuration` in milliseconds.
/// A seek time no `SeekStep` matches, set by another Stremio app, reads as the default and is
/// kept until the user picks another.
enum CorePlaybackSettings {
    static let audioLanguages = CoreLanguageKeys(primary: "audioLanguage", fallback: "secondaryAudioLanguage")
    private static let seekTimeKey = "seekTimeDuration"

    static func seekStep(in settings: [String: JSONValue]) -> SeekStep {
        guard case .number(let milliseconds)? = settings[seekTimeKey] else { return .defaults }
        return SeekStep.allCases.first { Double($0.seconds * 1_000) == milliseconds } ?? .defaults
    }

    /// Leaves the key as it is when it already reads as `step`.
    static func write(_ step: SeekStep, into settings: inout [String: JSONValue]) {
        guard seekStep(in: settings) != step else { return }
        settings[seekTimeKey] = .number(Double(step.seconds * 1_000))
    }
}

/// The settings keys of a preferred language and the one to fall back on. A primary that is
/// missing or not a language code reads as no preference.
struct CoreLanguageKeys {
    let primary: String
    let fallback: String

    func read(_ settings: [String: JSONValue]) -> PreferredLanguages? {
        guard let primary = Self.language(settings[primary]) else { return nil }
        return PreferredLanguages(primary: primary, fallback: Self.language(settings[fallback]))
    }

    func write(_ languages: PreferredLanguages?, into settings: inout [String: JSONValue]) {
        settings[primary] = languages.map { .string($0.primary.code) } ?? .null
        settings[fallback] = languages?.fallback.map { .string($0.code) } ?? .null
    }

    private static func language(_ value: JSONValue?) -> Language? {
        guard case .string(let code)? = value else { return nil }
        return Language(code)
    }
}
