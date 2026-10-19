import Foundation
import Testing

struct CoreSubtitleSettingsTests {
    /// The subtitle keys of a fresh core profile.
    private static let coreDefaults: [String: JSONValue] = [
        "subtitlesLanguage": .string("eng"),
        "secondarySubtitlesLanguage": .null,
        "subtitlesAutoSelect": .bool(true),
        "subtitlesSize": .number(100),
        "subtitlesFont": .string("Roboto"),
        "subtitlesBold": .bool(false),
        "subtitlesOffset": .number(5),
        "subtitlesTextColor": .string("#FFFFFFFF"),
        "subtitlesBackgroundColor": .string("#00000000"),
        "subtitlesOutlineColor": .string("#000000"),
        "subtitlesOpacity": .number(100),
        "assSubtitlesStyling": .bool(false),
    ]

    private let english = Language("eng").require()
    private let polish = Language("pol").require()

    @Test func coreDefaultsReadAsTheDefaultStyle() {
        #expect(CoreSubtitleSettings.style(in: Self.coreDefaults) == .defaults)
        #expect(CoreSubtitleSettings.languages(in: Self.coreDefaults) == PreferredLanguages(primary: english, fallback: nil))
    }

    @Test func colorsReadWithAndWithoutAlpha() {
        var settings = Self.coreDefaults
        settings["subtitlesTextColor"] = .string("#ffcc00")
        settings["subtitlesBackgroundColor"] = .string("#11223380")
        let style = CoreSubtitleSettings.style(in: settings)
        #expect(style.textColor == SubtitleColor(red: 255, green: 204, blue: 0, alpha: 255))
        #expect(style.backgroundColor == SubtitleColor(red: 17, green: 34, blue: 51, alpha: 128))
    }

    @Test func unreadableOrMissingKeysReadAsTheirDefault() {
        let settings: [String: JSONValue] = [
            "subtitlesSize": .number(150),
            "subtitlesTextColor": .string("yellow"),
            "subtitlesOutlineColor": .string("#12345"),
            "subtitlesBackgroundColor": .string("#+1234567"),
            "subtitlesOpacity": .number(300),
            "subtitlesOffset": .string("10"),
        ]
        var expected = SubtitleStyle.defaults
        expected.size = Percent(150)
        #expect(CoreSubtitleSettings.style(in: settings) == expected)
    }

    @Test func fileStylingReadsFromTheASSKey() {
        var settings = Self.coreDefaults
        settings["assSubtitlesStyling"] = .bool(true)
        #expect(CoreSubtitleSettings.style(in: settings).usesFileStyling)
        settings["assSubtitlesStyling"] = .string("true")
        #expect(!CoreSubtitleSettings.style(in: settings).usesFileStyling)
    }

    @Test func fontsReadByFamilyAndAnyOtherIsTheSystemFont() {
        let fonts = ["ui-rounded", "serif", "monospace", "sans-serif", "Roboto"].map { name in
            CoreSubtitleSettings.style(in: ["subtitlesFont": .string(name)]).font
        }
        #expect(fonts == [.rounded, .serif, .monospaced, .system, .system])
    }

    @Test func writingTheStyleWritesUppercaseHexWithAlpha() {
        let style = SubtitleStyle(
            size: Percent(125), font: .serif, isBold: true, usesFileStyling: true,
            textColor: SubtitleColor(red: 255, green: 204, blue: 0),
            outlineColor: SubtitleColor(red: 0, green: 0, blue: 0, alpha: 0),
            backgroundColor: SubtitleColor(red: 0, green: 0, blue: 0, alpha: 128),
            opacity: Percent(75), bottomOffset: Percent(10)
        )
        var settings = Self.coreDefaults
        CoreSubtitleSettings.write(style, into: &settings)
        #expect(settings["subtitlesSize"] == .number(125))
        #expect(settings["subtitlesFont"] == .string("serif"))
        #expect(settings["subtitlesBold"] == .bool(true))
        #expect(settings["assSubtitlesStyling"] == .bool(true))
        #expect(settings["subtitlesTextColor"] == .string("#FFCC00FF"))
        #expect(settings["subtitlesOutlineColor"] == .string("#00000000"))
        #expect(settings["subtitlesBackgroundColor"] == .string("#00000080"))
        #expect(settings["subtitlesOpacity"] == .number(75))
        #expect(settings["subtitlesOffset"] == .number(10))
        #expect(CoreSubtitleSettings.style(in: settings) == style)
    }

    @Test func aFontReadingAsTheSystemFontIsKept() {
        var settings = Self.coreDefaults
        var style = SubtitleStyle.defaults
        style.isBold = true
        CoreSubtitleSettings.write(style, into: &settings)
        #expect(settings["subtitlesFont"] == .string("Roboto"))
        style.font = .monospaced
        CoreSubtitleSettings.write(style, into: &settings)
        #expect(settings["subtitlesFont"] == .string("monospace"))
        style.font = .system
        CoreSubtitleSettings.write(style, into: &settings)
        #expect(settings["subtitlesFont"] == .string("sans-serif"))
    }

    @Test func aSecondLanguageNeedsAFirst() {
        var settings = Self.coreDefaults
        settings["subtitlesLanguage"] = .null
        settings["secondarySubtitlesLanguage"] = .string("pol")
        #expect(CoreSubtitleSettings.languages(in: settings) == nil)
    }

    @Test func autoSelectOffReadsAsNoSubtitles() {
        var settings = Self.coreDefaults
        settings["subtitlesAutoSelect"] = .bool(false)
        #expect(CoreSubtitleSettings.languages(in: settings) == nil)
        settings["subtitlesAutoSelect"] = nil
        #expect(CoreSubtitleSettings.languages(in: settings) == PreferredLanguages(primary: english, fallback: nil))
    }

    @Test func languagesWriteBothKeysAndAutoSelect() {
        var settings = Self.coreDefaults
        CoreSubtitleSettings.write(PreferredLanguages(primary: polish, fallback: english), into: &settings)
        #expect(settings["subtitlesLanguage"] == .string("pol"))
        #expect(settings["secondarySubtitlesLanguage"] == .string("eng"))
        #expect(settings["subtitlesAutoSelect"] == .bool(true))
        #expect(CoreSubtitleSettings.languages(in: settings) == PreferredLanguages(primary: polish, fallback: english))
        CoreSubtitleSettings.write(nil, into: &settings)
        #expect(settings["subtitlesLanguage"] == .null)
        #expect(settings["secondarySubtitlesLanguage"] == .null)
        #expect(settings["subtitlesAutoSelect"] == .bool(false))
    }

    @Test func languagesKeptWhileAutoSelectIsOffSurviveAnUnchangedWrite() {
        var settings = Self.coreDefaults
        settings["subtitlesAutoSelect"] = .bool(false)
        CoreSubtitleSettings.write(nil, into: &settings)
        #expect(settings["subtitlesLanguage"] == .string("eng"))
        #expect(settings["subtitlesAutoSelect"] == .bool(false))
    }
}
