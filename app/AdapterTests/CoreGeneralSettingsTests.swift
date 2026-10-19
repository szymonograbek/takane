import Foundation
import Testing

struct CoreGeneralSettingsTests {
    /// The audio and seek keys of a fresh core profile.
    private static let coreDefaults: [String: JSONValue] = [
        "audioLanguage": .string("eng"),
        "secondaryAudioLanguage": .null,
        "seekTimeDuration": .number(10_000),
        "seekShortTimeDuration": .number(3_000),
        "hideSpoilers": .bool(false),
    ]

    private let english = Language("eng").require()
    private let polish = Language("pol").require()

    @Test func coreDefaultsRead() {
        #expect(CoreGeneralSettings.audioLanguages.read(Self.coreDefaults) == PreferredLanguages(primary: english, fallback: nil))
        #expect(CoreGeneralSettings.seekStep(in: Self.coreDefaults) == .ten)
        #expect(CoreGeneralSettings.hidesSpoilers(in: Self.coreDefaults) == false)
    }

    @Test func audioLanguagesWriteBothKeys() {
        var settings = Self.coreDefaults
        CoreGeneralSettings.audioLanguages.write(PreferredLanguages(primary: polish, fallback: english), into: &settings)
        #expect(settings["audioLanguage"] == .string("pol"))
        #expect(settings["secondaryAudioLanguage"] == .string("eng"))
        CoreGeneralSettings.audioLanguages.write(nil, into: &settings)
        #expect(settings["audioLanguage"] == .null)
        #expect(settings["secondaryAudioLanguage"] == .null)
    }

    @Test func seekTimesReadInMillisecondsAndAnyOtherIsTheDefault() {
        let steps = [5_000, 15_000, 30_000, 20_000].map { milliseconds in
            CoreGeneralSettings.seekStep(in: ["seekTimeDuration": .number(Double(milliseconds))])
        }
        #expect(steps == [.five, .fifteen, .thirty, .ten])
        #expect(CoreGeneralSettings.seekStep(in: [:]) == .ten)
    }

    @Test func aSeekTimeReadingAsTheChosenStepIsKept() {
        var settings = Self.coreDefaults
        settings["seekTimeDuration"] = .number(20_000)
        CoreGeneralSettings.write(.ten, into: &settings)
        #expect(settings["seekTimeDuration"] == .number(20_000))
        CoreGeneralSettings.write(.thirty, into: &settings)
        #expect(settings["seekTimeDuration"] == .number(30_000))
        #expect(settings["seekShortTimeDuration"] == .number(3_000))
    }

    @Test func hideSpoilersReadsAsFalseUnlessTrue() {
        #expect(CoreGeneralSettings.hidesSpoilers(in: ["hideSpoilers": .bool(true)]) == true)
        #expect(CoreGeneralSettings.hidesSpoilers(in: ["hideSpoilers": .string("yes")]) == false)
        #expect(CoreGeneralSettings.hidesSpoilers(in: [:]) == false)
    }

    @Test func hideSpoilersWritesItsKey() {
        var settings = Self.coreDefaults
        CoreGeneralSettings.writeHidesSpoilers(true, into: &settings)
        #expect(settings["hideSpoilers"] == .bool(true))
        CoreGeneralSettings.writeHidesSpoilers(false, into: &settings)
        #expect(settings["hideSpoilers"] == .bool(false))
        #expect(settings["seekTimeDuration"] == .number(10_000))
    }
}
