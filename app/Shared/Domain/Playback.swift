import CoreGraphics
import Foundation

struct VideoSize: Hashable, Sendable {
    let width: Int
    let height: Int
}

enum TrackKind: Hashable, Sendable {
    case audio
    case subtitle
}

/// An audio or subtitle track of the playing stream.
struct MediaTrack: Identifiable, Hashable, Sendable {
    struct ID: Hashable, Sendable {
        let kind: TrackKind
        /// The engine's number for the track, unique within its kind.
        let number: Int
    }

    let id: ID
    /// Files often carry their release's name in it.
    let title: Redacted<String>?
    /// As the stream labels it, usually an ISO 639 code such as `eng`.
    let language: String?
    let codec: String?
    /// Audio only.
    let channelCount: Int?
    let isForced: Bool
    /// The file the track was added from, such as an add-on subtitle. Nil for the stream's own tracks.
    let externalFile: Redacted<URL>?
    let isSelected: Bool
}

/// A playback rate the player offers.
enum PlaybackSpeed: Double, CaseIterable, Hashable, Sendable {
    case half = 0.5
    case threeQuarters = 0.75
    case normal = 1
    case oneAndAQuarter = 1.25
    case oneAndAHalf = 1.5
    case double = 2
}

/// Languages to pick tracks in when a stream starts, as ISO 639-2 codes.
struct TrackLanguages: Hashable, Sendable {
    /// Nil leaves it to the stream.
    var audio: PreferredLanguages?
    /// Nil starts streams without subtitles.
    var subtitles: PreferredLanguages?

    static let streamDefaults = TrackLanguages(audio: nil, subtitles: nil)
}

/// A language to prefer, and one to fall back on when a stream has none in it.
struct PreferredLanguages: Hashable, Sendable {
    var primary: Language
    var fallback: Language?

    /// Most preferred first.
    var inPreferenceOrder: [Language] {
        [primary] + (fallback.map { [$0] } ?? [])
    }
}

/// A subtitle on screen.
enum SubtitleCue: Equatable, Sendable {
    case text(SubtitleText)
    /// A rendered bitmap, such as a Blu-ray subtitle. `frame` places it as a fraction of the
    /// video frame, origin at the top left.
    case image(CGImage, frame: CGRect)
}

/// Subtitle text as the file styles and places it. Lines are separated by newlines.
struct SubtitleText: Hashable, Sendable {
    var runs: [SubtitleRun]
    /// Nil leaves the text to the player, centered above the picture's bottom edge.
    var placement: SubtitlePlacement?
}

extension SubtitleText {
    /// Unstyled text, placed by the player.
    init(_ plain: String) {
        self.init(runs: [SubtitleRun(text: Redacted(plain))], placement: nil)
    }
}

/// A span of subtitle text styled alike.
struct SubtitleRun: Hashable, Sendable {
    /// A line of the title's dialogue, which says what is playing.
    var text: Redacted<String>
    var isBold = false
    var isItalic = false
    var isUnderlined = false
    var isStruckThrough = false
    /// Nil keeps the text color of the user's style.
    var color: SubtitleColor?
    /// A font family by name. Nil keeps the font of the user's style.
    var fontName: String?
}

/// Where a subtitle file asks its text to be drawn.
struct SubtitlePlacement: Hashable, Sendable {
    /// The edge or corner of the picture the text sits at, or, with a `position`, the point of the
    /// text's block that sits on it.
    var alignment: SubtitleAlignment
    /// A point on the picture as a fraction of its size, origin at the top left. It may lie outside
    /// the picture.
    var position: CGPoint?
}

/// One of nine anchors: an edge, a corner or the center.
struct SubtitleAlignment: Hashable, Sendable {
    enum Horizontal: Hashable, Sendable {
        case leading
        case center
        case trailing
    }

    enum Vertical: Hashable, Sendable {
        case top
        case middle
        case bottom
    }

    /// Where the player draws text that no file places.
    static let bottomCenter = SubtitleAlignment(horizontal: .center, vertical: .bottom)

    let horizontal: Horizontal
    let vertical: Vertical

    init(horizontal: Horizontal, vertical: Vertical) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// An ASS numpad alignment (`\an`): 1 to 3 along the bottom, 4 to 6 through the middle and 7 to 9
    /// along the top, each row left to right.
    init?(numpad: Int) {
        guard (1...9).contains(numpad) else { return nil }
        let columns: [Horizontal] = [.leading, .center, .trailing]
        let rows: [Vertical] = [.bottom, .middle, .top]
        self.init(horizontal: columns[(numpad - 1) % 3], vertical: rows[(numpad - 1) / 3])
    }
}

/// What a playback engine reports, in the order it happened.
enum PlaybackEvent: Equatable, Sendable {
    case loaded
    /// The stream played to its end.
    case ended
    /// Playback stopped on request, or the file was replaced by a newer load.
    case stopped
    case failed(reason: String)
    case position(Duration)
    /// A seek started toward this position, before the position moves there. Until the seek ends,
    /// positions are its target, never the one it left.
    case seeking(to: Duration)
    case duration(Duration)
    case paused(Bool)
    case buffering(Bool)
    case videoSize(VideoSize?)
    /// The decoder of the video, such as `VideoToolbox HEVC (HW)`.
    case decoder(String)
    /// Every audio and subtitle track, after any change to the list or the selection.
    case tracks([MediaTrack])
    /// A rate the engine reports that is not one of `PlaybackSpeed` is left out.
    case speed(PlaybackSpeed)
    /// The subtitles to show now, replacing the previous ones. Empty when none is visible.
    case subtitles([SubtitleCue])
    /// Every cue the selected subtitle track holds so far, timed like `position`, after any change
    /// to them. Empty without one.
    case cueTimeline([TimedCue])
}

enum PlaybackError: Error, Equatable, Sendable {
    case unsupported(kind: String)
    case failed(reason: String)
}

/// Decodes and renders streams. The view video renders into belongs to the provider, so the
/// composition root hands it to the UI (`Services.videoSurface`).
@MainActor
protocol PlaybackEngine: AnyObject, Sendable {
    /// Every event for the engine's lifetime. Iterate it from one place only.
    var events: AsyncStream<PlaybackEvent> { get }

    /// Plays `source` from `start`, picking tracks in `languages` when the stream has them.
    func load(_ source: PlaybackSource, from start: Duration, languages: TrackLanguages)
    func setPaused(_ paused: Bool)
    func seek(by offset: Duration)
    func seek(to position: Duration)
    func select(_ track: MediaTrack.ID)
    func turnOffSubtitles()
    /// Adds a subtitle file, fetched from `source`, as a track and selects it. The track's
    /// `externalFile` is `file`. A file that fails to load is logged.
    func addSubtitles(_ file: Redacted<URL>, from source: PlaybackSource, title: String, language: String)
    func setSpeed(_ speed: PlaybackSpeed)
    /// Shows the subtitles `delay` away from their file's times, at once. A new load starts at zero.
    func setSubtitleDelay(_ delay: SubtitleDelay)
    /// Where people spoke in `range` of the current stream, from the audio played since it loaded.
    func speechActivity(in range: Range<Duration>) -> SpeechActivity
    func stop()
    /// Output health by name (route, decoders, audio delivery, frame counters), for logs and the smoke test.
    func diagnostics() -> [String: String]
    /// The current frame, when the platform supports reading it back.
    func snapshot() async -> CGImage?
}

/// The tracks, subtitle timing and speed the viewer chose for a title, remembered so it plays the
/// same way next time.
struct TrackChoices: Hashable, Sendable {
    /// A track by the engine's number and its language. Another file, such as the next episode, may
    /// number its tracks differently, so the language confirms the number.
    struct Track: Hashable, Sendable {
        let number: Int
        let language: String?
    }

    enum Subtitles: Hashable, Sendable {
        case builtIn(Track)
        /// An add-on's file, by its address.
        case addon(Redacted<URL>, language: String?)
    }

    /// Nil when none was chosen.
    var audio: Track?
    /// Nil when subtitles are off or none was chosen.
    var subtitles: Subtitles?
    /// Nil when none was chosen.
    var speed: PlaybackSpeed?
    /// The timing of `subtitles`, which another file would not share.
    var subtitleDelay = SubtitleDelay.zero
}

/// The episode after the one playing.
struct UpNext: Equatable, Sendable {
    let video: PlayableID
    /// The series it belongs to, such as "Twin Peaks".
    let show: Redacted<String>
    /// The episode's own title. Empty when the add-on gives none.
    let title: Redacted<String>
    let thumbnail: URL?
    /// The series' backdrop.
    let backdrop: URL?
    /// A stream for it like the one playing, from the same add-on, that plays here. Nil leaves the
    /// choice of stream to the viewer.
    let stream: StreamCandidate?
}

/// Records what the user watched, so progress, watched state and continue watching follow playback,
/// and finds what to watch next.
protocol PlaybackTracker: Sendable {
    func begin(_ candidate: StreamCandidate)
    func progress(_ position: Duration, of duration: Duration)
    /// The viewer moved to `position` without watching the time in between.
    func seek(to position: Duration, of duration: Duration)
    func paused(_ paused: Bool)
    func ended()
    /// The viewer moved on to the next episode. Call it before beginning that episode.
    func movedToNext()
    func stop()
    /// Remembers what the viewer chose for the candidate being tracked.
    func remember(_ choices: TrackChoices)
    /// What was remembered for `candidate`, playing from `source`, or carried over from an earlier
    /// episode, once known. Call it after `begin(candidate)`. Yields at most once, and finishes once
    /// another candidate replaces it.
    func remembered(for candidate: StreamCandidate, playing source: PlaybackSource) -> AsyncStream<TrackChoices>
    /// The episode after `candidate`, now and after every change, nil while there is none or it is
    /// not known yet. Finishes once another candidate replaces it.
    func upNext(after candidate: StreamCandidate) -> AsyncStream<UpNext?>
}
