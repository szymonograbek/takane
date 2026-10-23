import Foundation

/// How far the subtitles are moved from the times their file gives them. Positive shows them
/// later, negative earlier. Never more than `limit` either way.
struct SubtitleDelay: Hashable, Sendable {
    /// How far one press moves the subtitles.
    enum Step: Sendable {
        /// A tap: 100 ms.
        case fine
        /// Each repeat while a press is held: 500 ms.
        case coarse

        var duration: Duration {
            switch self {
            case .fine: .milliseconds(100)
            case .coarse: .milliseconds(500)
            }
        }
    }

    static let limit = Duration.seconds(30)
    static let zero = SubtitleDelay(clamping: .zero)

    let duration: Duration

    init(clamping duration: Duration) {
        self.duration = min(max(duration, .zero - Self.limit), Self.limit)
    }

    func moved(by offset: Duration) -> SubtitleDelay {
        SubtitleDelay(clamping: duration + offset)
    }
}

/// A subtitle of the selected track, by when it shows.
struct TimedCue: Identifiable, Hashable, Sendable {
    struct ID: Hashable, Sendable {
        /// The engine's number for the cue, unique within a load.
        let number: Int
    }

    let id: ID
    /// When it shows, timed like the playback position, before any `SubtitleDelay`.
    let range: Range<Duration>
    /// Its first line, a line of the title's dialogue. Empty for a bitmap subtitle.
    let text: Redacted<String>
}
