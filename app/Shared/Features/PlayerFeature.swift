import Foundation

/// Plays one stream at a time and keeps the tracker informed of progress.
enum PlayerFeature: Feature {
    struct Dependencies: Sendable {
        let engine: any PlaybackEngine
        let tracker: any PlaybackTracker
    }

    enum Phase: String, Sendable {
        case opening, playing, paused, ended
    }

    struct Session: Equatable, Sendable {
        let candidate: StreamCandidate
        var phase = Phase.opening
        var position = Duration.zero
        /// Zero until the engine knows it.
        var duration = Duration.zero
        var isBuffering = false
        var videoSize: VideoSize?
        var hardwareDecoder: String?
        /// The whole second last reported to the tracker.
        var reportedSecond: Int64?
    }

    enum State: Equatable, Sendable {
        case idle
        case active(Session)
        case failed(StreamCandidate, PlaybackError)
    }

    enum Event: Sendable {
        case open(StreamCandidate)
        case togglePause
        case seek(by: Duration)
        case stop
        case engine(PlaybackEvent)
    }

    enum Report: Equatable, Sendable {
        case progress(Duration, of: Duration)
        case paused(Bool)
        case ended
    }

    enum Effect: Equatable, Sendable {
        /// Feeds engine events back as `.engine`. Start it once, when the store is created.
        case listen
        case begin(StreamCandidate, PlaybackSource)
        case setPaused(Bool)
        case seek(by: Duration)
        case stop
        case report(Report)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state, event) {
        case (_, .open(let candidate)):
            switch candidate.playability {
            case .playable(let source):
                state = .active(Session(candidate: candidate))
                return [.begin(candidate, source)]
            case .unsupported(let kind):
                let wasActive = state.session != nil
                state = .failed(candidate, .unsupported(kind: kind))
                return wasActive ? [.stop] : []
            }

        case (.active(let session), .togglePause):
            switch session.phase {
            case .playing: return [.setPaused(true)]
            case .paused: return [.setPaused(false)]
            case .opening, .ended: return []
            }

        case (.active, .seek(let offset)):
            return [.seek(by: offset)]

        case (.active, .stop), (.failed, .stop):
            state = .idle
            return [.stop]

        case (.active(var session), .engine(let event)):
            let effects = apply(event, to: &session)
            switch event {
            case .failed(let reason): state = .failed(session.candidate, .failed(reason: reason))
            case .stopped where session.phase != .opening: state = .idle
            default: state = .active(session)
            }
            return effects

        case (.idle, .togglePause), (.idle, .seek), (.idle, .stop), (.idle, .engine),
             (.failed, .togglePause), (.failed, .seek), (.failed, .engine):
            return []
        }
    }

    /// Updates `session` for an engine event. A `.stopped` while opening is the previous file
    /// making way for this one, so it changes nothing.
    private static func apply(_ event: PlaybackEvent, to session: inout Session) -> [Effect] {
        switch event {
        case .loaded:
            session.phase = .playing
        case .ended:
            session.phase = .ended
            return [.report(.ended)]
        case .stopped, .failed:
            break
        case .position(let reported):
            // Engines can report a slightly negative position for streams starting before PTS 0.
            let position = max(.zero, reported)
            session.position = position
            let second = position.components.seconds
            guard second != session.reportedSecond, session.duration > .zero else { return [] }
            session.reportedSecond = second
            return [.report(.progress(position, of: session.duration))]
        case .duration(let duration):
            session.duration = duration
        case .paused(let paused):
            switch session.phase {
            case .playing where paused: session.phase = .paused
            case .paused where !paused: session.phase = .playing
            case .opening, .playing, .paused, .ended: break
            }
            return [.report(.paused(paused))]
        case .buffering(let buffering):
            session.isBuffering = buffering
        case .videoSize(let size):
            session.videoSize = size
        case .hardwareDecoder(let name):
            session.hardwareDecoder = name
        }
        return []
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        let engine = dependencies.engine
        let tracker = dependencies.tracker
        switch effect {
        case .listen:
            for await event in engine.events {
                send(.engine(event))
            }
        case .begin(let candidate, let source):
            tracker.begin(candidate)
            engine.load(source)
            engine.setPaused(false)
        case .setPaused(let paused):
            engine.setPaused(paused)
        case .seek(let offset):
            engine.seek(by: offset)
        case .stop:
            engine.stop()
            tracker.stop()
        case .report(.progress(let position, let duration)):
            tracker.progress(position, of: duration)
        case .report(.paused(let paused)):
            tracker.paused(paused)
        case .report(.ended):
            tracker.ended()
        }
    }
}

extension PlayerFeature.State {
    var session: PlayerFeature.Session? {
        if case .active(let session) = self { session } else { nil }
    }

    /// The candidate on screen, playing or failed.
    var candidate: StreamCandidate? {
        switch self {
        case .idle: nil
        case .active(let session): session.candidate
        case .failed(let candidate, _): candidate
        }
    }

    var phaseName: String {
        switch self {
        case .idle: "idle"
        case .active(let session): session.phase.rawValue
        case .failed(_, let error): "failed: \(error)"
        }
    }
}

extension PlayerFeature.State {
    /// Position, duration, phase, video size and decoder, such as `0:00:10 / 2:22:32 · playing · 1920×1080 · hwdec no`.
    var statusLine: String {
        let session = session
        var parts = [phaseName]
        if let size = session?.videoSize { parts.append("\(size.width)×\(size.height)") }
        if let decoder = session?.hardwareDecoder { parts.append("hwdec \(decoder)") }
        let time = "\(Self.clock(session?.position ?? .zero)) / \(Self.clock(session?.duration ?? .zero))"
        return ([time] + parts).joined(separator: " · ")
    }

    private static func clock(_ duration: Duration) -> String {
        let total = Int(duration.components.seconds)
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}
