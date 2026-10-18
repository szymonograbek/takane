import CoreGraphics
import Foundation
import QuartzCore

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

/// Languages to pick tracks in when a stream starts, as ISO 639-2 codes. Nil leaves it to the stream.
struct TrackLanguages: Hashable, Sendable {
    var audio: Language?
    var subtitles: Language?

    static let streamDefaults = TrackLanguages(audio: nil, subtitles: nil)
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
    case hardwareDecoder(String)
    /// Every audio and subtitle track, after any change to the list or the selection.
    case tracks([MediaTrack])
    /// A rate the engine reports that is not one of `PlaybackSpeed` is left out.
    case speed(PlaybackSpeed)
}

enum PlaybackError: Error, Equatable, Sendable {
    case unsupported(kind: String)
    case failed(reason: String)
}

/// Decodes and renders streams.
@MainActor
protocol PlaybackEngine: AnyObject, Sendable {
    /// The layer video renders into.
    var surface: CAMetalLayer { get }
    /// Every event for the engine's lifetime. Iterate it from one place only.
    var events: AsyncStream<PlaybackEvent> { get }

    /// Starts `source` at `start`, picking tracks in `languages` when the stream has them.
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
    /// Output health by engine property name, for logs and the smoke test.
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
