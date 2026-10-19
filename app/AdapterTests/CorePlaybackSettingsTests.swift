import Foundation
import Testing

struct CorePlaybackSettingsTests {
    /// The audio and seek keys of a fresh core profile.
    private static let coreDefaults: [String: JSONValue] = [
        "audioLanguage": .string("eng"),
        "secondaryAudioLanguage": .null,
        "seekTimeDuration": .number(10_000),
        "seekShortTimeDuration": .number(3_000),
    ]

    private let english = Language("eng").require()
    private let polish = Language("pol").require()

    @Test func coreDefaultsRead() {
        #expect(CorePlaybackSettings.audioLanguages.read(Self.coreDefaults) == PreferredLanguages(primary: english, fallback: nil))
        #expect(CorePlaybackSettings.seekStep(in: Self.coreDefaults) == .ten)
    }

    @Test func audioLanguagesWriteBothKeys() {
        var settings = Self.coreDefaults
        CorePlaybackSettings.audioLanguages.write(PreferredLanguages(primary: polish, fallback: english), into: &settings)
        #expect(settings["audioLanguage"] == .string("pol"))
        #expect(settings["secondaryAudioLanguage"] == .string("eng"))
        CorePlaybackSettings.audioLanguages.write(nil, into: &settings)
        #expect(settings["audioLanguage"] == .null)
        #expect(settings["secondaryAudioLanguage"] == .null)
    }

    @Test func seekTimesReadInMillisecondsAndAnyOtherIsTheDefault() {
        let steps = [5_000, 15_000, 30_000, 20_000].map { milliseconds in
            CorePlaybackSettings.seekStep(in: ["seekTimeDuration": .number(Double(milliseconds))])
        }
        #expect(steps == [.five, .fifteen, .thirty, .ten])
        #expect(CorePlaybackSettings.seekStep(in: [:]) == .ten)
    }

    @Test func aSeekTimeReadingAsTheChosenStepIsKept() {
        var settings = Self.coreDefaults
        settings["seekTimeDuration"] = .number(20_000)
        CorePlaybackSettings.write(.ten, into: &settings)
        #expect(settings["seekTimeDuration"] == .number(20_000))
        CorePlaybackSettings.write(.thirty, into: &settings)
        #expect(settings["seekTimeDuration"] == .number(30_000))
        #expect(settings["seekShortTimeDuration"] == .number(3_000))
    }
}
