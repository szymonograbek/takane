import Foundation

/// Subtitle preferences as core's profile settings hold them: `subtitlesLanguage` and
/// `secondarySubtitlesLanguage`, then the style keys (`subtitlesSize`, `subtitlesTextColor`…) and
/// `assSubtitlesStyling`, which keeps a file's own styling.
/// Colors are CSS hex, `#RRGGBB` or `#RRGGBBAA`; sizes, opacity and offset are whole percents.
/// A key that is missing or unreadable reads as its default.
enum CoreSubtitleSettings {
    static func languages(in settings: [String: JSONValue]) -> SubtitleLanguages {
        guard let primary = language(settings[Key.language]) else { return .off }
        return .preferred(primary, fallback: language(settings[Key.secondaryLanguage]))
    }

    static func style(in settings: [String: JSONValue]) -> SubtitleStyle {
        let defaults = SubtitleStyle.defaults
        return SubtitleStyle(
            size: percent(settings[Key.size]) ?? defaults.size,
            font: font(settings[Key.font]),
            isBold: flag(settings[Key.bold], or: defaults.isBold),
            usesFileStyling: flag(settings[Key.fileStyling], or: defaults.usesFileStyling),
            textColor: color(settings[Key.textColor]) ?? defaults.textColor,
            outlineColor: color(settings[Key.outlineColor]) ?? defaults.outlineColor,
            backgroundColor: color(settings[Key.backgroundColor]) ?? defaults.backgroundColor,
            opacity: percent(settings[Key.opacity]) ?? defaults.opacity,
            bottomOffset: percent(settings[Key.offset]) ?? defaults.bottomOffset
        )
    }

    static func write(_ languages: SubtitleLanguages, into settings: inout [String: JSONValue]) {
        switch languages {
        case .off:
            settings[Key.language] = .null
            settings[Key.secondaryLanguage] = .null
        case .preferred(let primary, let fallback):
            settings[Key.language] = .string(primary.code)
            settings[Key.secondaryLanguage] = fallback.map { .string($0.code) } ?? .null
        }
    }

    static func write(_ style: SubtitleStyle, into settings: inout [String: JSONValue]) {
        settings[Key.size] = .number(Double(style.size.value))
        // Many font names read as the system font, so one another Stremio app chose survives other edits.
        if font(settings[Key.font]) != style.font {
            settings[Key.font] = .string(fontName(style.font))
        }
        settings[Key.bold] = .bool(style.isBold)
        settings[Key.fileStyling] = .bool(style.usesFileStyling)
        settings[Key.textColor] = .string(hex(style.textColor))
        settings[Key.outlineColor] = .string(hex(style.outlineColor))
        settings[Key.backgroundColor] = .string(hex(style.backgroundColor))
        settings[Key.opacity] = .number(Double(style.opacity.value))
        settings[Key.offset] = .number(Double(style.bottomOffset.value))
    }

    private enum Key {
        static let language = "subtitlesLanguage"
        static let secondaryLanguage = "secondarySubtitlesLanguage"
        static let size = "subtitlesSize"
        static let font = "subtitlesFont"
        static let bold = "subtitlesBold"
        static let fileStyling = "assSubtitlesStyling"
        static let offset = "subtitlesOffset"
        static let textColor = "subtitlesTextColor"
        static let backgroundColor = "subtitlesBackgroundColor"
        static let outlineColor = "subtitlesOutlineColor"
        static let opacity = "subtitlesOpacity"
    }

    private static func language(_ value: JSONValue?) -> Language? {
        guard case .string(let code)? = value else { return nil }
        return Language(code)
    }

    private static func flag(_ value: JSONValue?, or fallback: Bool) -> Bool {
        guard case .bool(let flag)? = value else { return fallback }
        return flag
    }

    private static func percent(_ value: JSONValue?) -> Percent? {
        guard case .number(let number)? = value, let whole = UInt8(exactly: number) else { return nil }
        return Percent(whole)
    }

    /// CSS font families. Any other family, such as Stremio's default Roboto, reads as the system font.
    private static func font(_ value: JSONValue?) -> SubtitleFont {
        guard case .string(let name)? = value else { return .system }
        return SubtitleFont.allCases.first { fontName($0) == name } ?? .system
    }

    private static func fontName(_ font: SubtitleFont) -> String {
        switch font {
        case .system: "sans-serif"
        case .rounded: "ui-rounded"
        case .serif: "serif"
        case .monospaced: "monospace"
        }
    }

    private static func color(_ value: JSONValue?) -> SubtitleColor? {
        guard case .string(let text)? = value, text.first == "#" else { return nil }
        let digits = text.dropFirst()
        guard digits.count == 6 || digits.count == 8, digits.allSatisfy(\.isHexDigit),
              let packed = UInt32(digits, radix: 16) else { return nil }
        let rgba = digits.count == 8 ? packed : packed << 8 | 0xFF
        return SubtitleColor(
            red: UInt8(truncatingIfNeeded: rgba >> 24),
            green: UInt8(truncatingIfNeeded: rgba >> 16),
            blue: UInt8(truncatingIfNeeded: rgba >> 8),
            alpha: UInt8(truncatingIfNeeded: rgba)
        )
    }

    private static func hex(_ color: SubtitleColor) -> String {
        String(format: "#%02X%02X%02X%02X", color.red, color.green, color.blue, color.alpha)
    }
}
