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

/// The user's settings, synced with the account when signed in.
protocol PreferencesService: Sendable {
    /// The preferences now, then after every change.
    func preferences() -> AsyncStream<Preferences>

    func update(_ preferences: Preferences) throws(PreferencesError)
}
