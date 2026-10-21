import Foundation

/// An ISO 639-2 language code, such as `eng`, as Stremio stores languages.
struct Language: Hashable, Sendable, CustomStringConvertible {
    let code: String

    init?(_ code: String) {
        let lowered = code.lowercased()
        guard lowered.count == 3, lowered.allSatisfy(\.isLetter) else { return nil }
        self.code = lowered
    }

    var description: String { code }
}

struct Preferences: Hashable, Sendable {
    var languages: TrackLanguages
    var subtitleStyle: SubtitleStyle
    var seekStep: SeekStep
    /// Whether a title's unwatched episodes keep their still blurred and their overview hidden.
    var hidesSpoilers: Bool
    var upNext: UpNextBehavior
    /// Kept on this device, not synced.
    var skipSegmentSource: SkipSegmentSource
}

/// How the player leads from an episode into the next.
struct UpNextBehavior: Hashable, Sendable {
    var notice: UpNextNotice
    /// Whether the next episode plays by itself when one ends, unless the viewer dismissed its offer.
    var autoplay: Bool

    static let defaults = UpNextBehavior(notice: .defaults, autoplay: true)
}

/// How long before an episode ends the player offers the next one.
enum UpNextNotice: Int, CaseIterable, Hashable, Sendable {
    case off = 0
    case tenSeconds = 10
    case twentySeconds = 20
    case thirtyFiveSeconds = 35
    case sixtySeconds = 60

    static let defaults = UpNextNotice.thirtyFiveSeconds

    /// Nil never offers it.
    var lead: Duration? {
        self == .off ? nil : .seconds(rawValue)
    }
}

/// How far one press of back or forward skips. Each has an SF Symbol, `gobackward.<seconds>`.
enum SeekStep: Int, CaseIterable, Hashable, Sendable {
    case five = 5
    case ten = 10
    case fifteen = 15
    case thirty = 30

    static let defaults = SeekStep.ten

    var seconds: Int { rawValue }
    var duration: Duration { .seconds(rawValue) }
}

enum PreferencesError: Error, Equatable, Sendable {
    case rejected(reason: String)
}

/// The user's settings, synced with the account when signed in unless a setting says otherwise.
protocol PreferencesService: Sendable {
    /// The preferences now, then after every change.
    func preferences() -> AsyncStream<Preferences>

    func update(_ preferences: Preferences) throws(PreferencesError)
}
