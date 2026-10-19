import Foundation

/// How text subtitles look. The defaults are Stremio's.
struct SubtitleStyle: Hashable, Sendable {
    /// Relative to the standard size.
    var size: Percent
    var font: SubtitleFont
    var isBold: Bool
    /// Keeps the colors, fonts and placement a subtitle file sets. Bold, italic, underline and
    /// strikethrough show either way.
    var usesFileStyling: Bool
    var textColor: SubtitleColor
    /// Drawn only when not fully transparent.
    var outlineColor: SubtitleColor
    /// The backing behind the text, drawn only when not fully transparent.
    var backgroundColor: SubtitleColor
    var opacity: Percent
    /// Space between the text and the picture's bottom edge, relative to the picture's height.
    var bottomOffset: Percent

    static let defaults = SubtitleStyle(
        size: Percent(100),
        font: .system,
        isBold: false,
        usesFileStyling: false,
        textColor: SubtitleColor(red: 255, green: 255, blue: 255),
        outlineColor: SubtitleColor(red: 0, green: 0, blue: 0),
        backgroundColor: SubtitleColor(red: 0, green: 0, blue: 0, alpha: 0),
        opacity: Percent(100),
        bottomOffset: Percent(5)
    )
}

/// A whole percentage, which may exceed 100.
struct Percent: Hashable, Sendable {
    let value: UInt8

    init(_ value: UInt8) {
        self.value = value
    }

    /// 100 % is 1.
    var fraction: Double { Double(value) / 100 }
}

/// An sRGB color with alpha, each channel 0 to 255.
struct SubtitleColor: Hashable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    /// 0 is fully transparent.
    let alpha: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var isVisible: Bool { alpha > 0 }
}

enum SubtitleFont: Hashable, Sendable, CaseIterable {
    case system
    case rounded
    case serif
    case monospaced
}
