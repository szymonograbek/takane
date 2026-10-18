import CoreGraphics
import QuartzCore

struct VideoSize: Hashable, Sendable {
    let width: Int
    let height: Int
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

    func load(_ source: PlaybackSource)
    func setPaused(_ paused: Bool)
    func seek(by offset: Duration)
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
