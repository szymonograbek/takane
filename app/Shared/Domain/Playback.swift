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
    let title: String?
    /// As the stream labels it, usually an ISO 639 code such as `eng`.
    let language: String?
    let codec: String?
    /// Audio only.
    let channelCount: Int?
    let isForced: Bool
    /// The file the track was added from, such as an add-on subtitle. Nil for the stream's own tracks.
    let externalFile: URL?
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
    var audio: Language?
    var subtitles: SubtitleLanguages

    static let streamDefaults = TrackLanguages(audio: nil, subtitles: .off)
}

/// Whether a stream starts with subtitles, and in which language.
enum SubtitleLanguages: Hashable, Sendable {
    case off
    /// A track in the first language, else one in `fallback`.
    case preferred(Language, fallback: Language?)

    var primary: Language? {
        switch self {
        case .off: nil
        case .preferred(let language, _): language
        }
    }

    /// Most preferred first; empty when off.
    var inPreferenceOrder: [Language] {
        switch self {
        case .off: []
        case .preferred(let language, let fallback): [language] + (fallback.map { [$0] } ?? [])
        }
    }
}

/// A subtitle on screen. Styled text arrives flattened to its characters.
enum SubtitleCue: Equatable, Sendable {
    /// Drawn centered at the bottom of the picture. Lines are separated by newlines.
    case text(String)
    /// A rendered bitmap, such as a Blu-ray subtitle. `frame` places it as a fraction of the
    /// video frame, origin at the top left.
    case image(CGImage, frame: CGRect)
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
    /// Adds a subtitle file as a track and selects it. A file that fails to load is logged.
    func addSubtitles(_ file: URL, title: String, language: String)
    func setSpeed(_ speed: PlaybackSpeed)
    func stop()
    /// Output health by name (route, decoders, audio delivery, frame counters), for logs and the smoke test.
    func diagnostics() -> [String: String]
    /// The current frame, when the platform supports reading it back.
    func snapshot() async -> CGImage?
}

/// Records what the user watched, so progress, watched state and continue watching follow playback.
protocol PlaybackTracker: Sendable {
    func begin(_ candidate: StreamCandidate)
    func progress(_ position: Duration, of duration: Duration)
    func paused(_ paused: Bool)
    func ended()
    func stop()
}
