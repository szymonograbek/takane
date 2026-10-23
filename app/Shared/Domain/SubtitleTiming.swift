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

/// Where people speak in a stretch of the stream, a `frameDuration` at a time.
struct SpeechActivity: Hashable, Sendable {
    enum Frame: Hashable, Sendable {
        /// The audio there has not played since the stream loaded, or not recently.
        case unheard
        case quiet
        case speech
    }

    static let frameDuration = Duration.milliseconds(100)
    static let empty = SpeechActivity(firstFrame: 0, frames: [])

    /// The number of the first frame, counted in `frameDuration`s from the stream's time zero.
    let firstFrame: Int
    let frames: [Frame]

    /// The stretch covered, in the stream's own time.
    var range: Range<Duration> {
        Self.frameDuration * firstFrame ..< Self.frameDuration * (firstFrame + frames.count)
    }

    /// The frames that overlap `range`.
    func slice(_ range: Range<Duration>) -> SpeechActivity {
        let lower = min(max(Self.frame(containing: range.lowerBound), firstFrame), firstFrame + frames.count)
        let upper = min(max(Self.frame(containing: range.upperBound - .nanoseconds(1)) + 1, lower), firstFrame + frames.count)
        return SpeechActivity(firstFrame: lower, frames: Array(frames[(lower - firstFrame) ..< (upper - firstFrame)]))
    }

    /// The number of the frame that holds `time`.
    static func frame(containing time: Duration) -> Int {
        Int((time / frameDuration).rounded(.down))
    }
}
