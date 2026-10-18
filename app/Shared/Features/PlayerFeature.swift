import Foundation

/// Plays one stream at a time and keeps the tracker informed of progress.
enum PlayerFeature: Feature {
    struct Dependencies: Sendable {
        let engine: any PlaybackEngine
        let tracker: any PlaybackTracker
        let skipSegments: any SkipSegmentService
        let preferences: any PreferencesService
        let subtitles: any SubtitleService
    }

    /// What shows as subtitles: nothing, one of the stream's own tracks, or a file from an add-on.
    enum SubtitleChoice: Hashable, Sendable {
        case off
        case builtIn(MediaTrack.ID)
        case addon(AddonSubtitle.ID)
    }

    enum Phase: String, Sendable {
        case opening, playing, paused, ended
    }

    struct Session: Equatable, Sendable {
        let candidate: StreamCandidate
        /// What the viewer chose, such as "Twin Peaks · S1 E3", for the controls.
        var title = ""
        var phase = Phase.opening
        var position = Duration.zero
        /// Zero until the engine knows it.
        var duration = Duration.zero
        var isBuffering = false
        var videoSize: VideoSize?
        var hardwareDecoder: String?
        /// The whole second last reported to the tracker.
        var reportedSecond: Int64?
        var tracks: [MediaTrack] = []
        /// What each add-on offers for this stream, apart from the stream's own tracks.
        var addonSubtitles: [SubtitleSource] = []
        var speed = PlaybackSpeed.normal
        /// Parts of the stream the viewer may skip, found once the duration is known.
        var segments: Remote<[SkipSegment], SkipSegmentError>?
    }

    enum State: Equatable, Sendable {
        case idle
        case active(Session)
        case failed(StreamCandidate, PlaybackError)
    }

    enum Event: Sendable {
        /// Plays `candidate` from `start`, such as a saved position, labelled `title`.
        case open(StreamCandidate, from: Duration = .zero, title: String = "")
        case togglePause
        case seek(by: Duration)
        case select(MediaTrack.ID)
        case chooseSubtitles(SubtitleChoice)
        case setSpeed(PlaybackSpeed)
        case skip(SkipSegment)
        case stop
        case engine(PlaybackEvent)
        case segmentsFound(PlayableID, Result<[SkipSegment], SkipSegmentError>)
        case subtitlesFound(StreamCandidate, [SubtitleSource])
    }

    enum Report: Equatable, Sendable {
        case progress(Duration, of: Duration)
        case paused(Bool)
        case ended
    }

    enum Effect: Equatable, Sendable {
        /// Feeds engine events back as `.engine`. Start it once, when the store is created.
        case listen
        /// Starts playback, then follows the add-ons' subtitles for it until another candidate replaces it.
        case begin(StreamCandidate, PlaybackSource, from: Duration)
        case setPaused(Bool)
        case seek(by: Duration)
        case seekTo(Duration)
        case select(MediaTrack.ID)
        case turnOffSubtitles
        case addSubtitles(AddonSubtitle)
        case setSpeed(PlaybackSpeed)
        case findSegments(PlayableID, duration: Duration)
        case stop
        case report(Report)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state, event) {
        case (_, .open(let candidate, let start, let title)):
            switch candidate.playability {
            case .playable(let source):
                state = .active(Session(candidate: candidate, title: title))
                return [.begin(candidate, source, from: start)]
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

        case (.active(let session), .select(let track)):
            return session.tracks.contains { $0.id == track && !$0.isSelected } ? [.select(track)] : []

        case (.active(let session), .chooseSubtitles(let choice)):
            return choose(choice, in: session)

        case (.active(let session), .setSpeed(let speed)):
            return speed == session.speed ? [] : [.setSpeed(speed)]

        case (.active(let session), .skip(let segment)):
            return session.segments?.value?.contains(segment) == true ? [.seekTo(segment.range.upperBound)] : []

        case (.active(var session), .segmentsFound(let item, let result)) where item == session.candidate.item:
            session.segments = switch result {
            case .success(let segments): .loaded(segments)
            case .failure(let error): .failed(error)
            }
            state = .active(session)
            return []

        case (.active(var session), .subtitlesFound(let candidate, let sources)) where candidate == session.candidate:
            session.addonSubtitles = sources
            state = .active(session)
            return []

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
             (.failed, .togglePause), (.failed, .seek), (.failed, .engine),
             (.idle, .select), (.idle, .chooseSubtitles), (.idle, .setSpeed), (.idle, .skip), (.idle, .segmentsFound),
             (.failed, .select), (.failed, .chooseSubtitles), (.failed, .setSpeed), (.failed, .skip), (.failed, .segmentsFound),
             (.idle, .subtitlesFound), (.failed, .subtitlesFound),
             (.active, .segmentsFound), (.active, .subtitlesFound):
            return []
        }
    }

    /// An add-on file plays from the track it was added as; one not added yet is added.
    private static func choose(_ choice: SubtitleChoice, in session: Session) -> [Effect] {
        switch choice {
        case .off:
            return session.subtitleChoice == .off ? [] : [.turnOffSubtitles]
        case .builtIn(let track):
            return session.tracks.contains { $0.id == track && $0.externalFile == nil && !$0.isSelected } ? [.select(track)] : []
        case .addon(let id):
            guard let subtitle = session.addonSubtitle(id) else { return [] }
            guard let track = session.tracks.first(where: { $0.externalFile == subtitle.url }) else { return [.addSubtitles(subtitle)] }
            return track.isSelected ? [] : [.select(track.id)]
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
            guard session.segments == nil, duration > .zero else { return [] }
            session.segments = .loading
            return [.findSegments(session.candidate.item, duration: duration)]
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
        case .tracks(let tracks):
            session.tracks = tracks
        case .speed(let speed):
            session.speed = speed
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
        case .begin(let candidate, let source, let start):
            // The first value is the current one, so this does not wait on the network.
            var preferences = dependencies.preferences.playback().makeAsyncIterator()
            let languages = await preferences.next()?.languages ?? .streamDefaults
            tracker.begin(candidate)
            engine.load(source, from: start, languages: languages)
            engine.setPaused(false)
            for await sources in dependencies.subtitles.subtitles(for: candidate, playing: source) {
                send(.subtitlesFound(candidate, sources))
            }
        case .setPaused(let paused):
            engine.setPaused(paused)
        case .seek(let offset):
            engine.seek(by: offset)
        case .seekTo(let position):
            engine.seek(to: position)
        case .select(let track):
            engine.select(track)
        case .turnOffSubtitles:
            engine.turnOffSubtitles()
        case .addSubtitles(let subtitle):
            engine.addSubtitles(subtitle.url, title: subtitle.label ?? subtitle.language, language: subtitle.language)
        case .setSpeed(let speed):
            engine.setSpeed(speed)
        case .findSegments(let item, let duration):
            do {
                let found = try await dependencies.skipSegments.segments(for: item, duration: duration)
                send(.segmentsFound(item, .success(found.segments)))
            } catch {
                send(.segmentsFound(item, .failure(error)))
            }
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

extension PlayerFeature.Session {
    /// The stream's own subtitle tracks, without files added from add-ons.
    var builtInSubtitles: [MediaTrack] {
        tracks.filter { $0.id.kind == .subtitle && $0.externalFile == nil }
    }

    var subtitleChoice: PlayerFeature.SubtitleChoice {
        guard let track = tracks.first(where: { $0.id.kind == .subtitle && $0.isSelected }) else { return .off }
        guard let file = track.externalFile else { return .builtIn(track.id) }
        let subtitle = addonSubtitles.lazy.compactMap(\.subtitles.value).joined().first { $0.url == file }
        return subtitle.map { .addon($0.id) } ?? .off
    }

    func addonSubtitle(_ id: AddonSubtitle.ID) -> AddonSubtitle? {
        addonSubtitles.first { $0.addon == id.addon }?.subtitles.value?.first { $0.id == id }
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

    /// The skippable segment playing now. Segments whose timestamps may not fit this cut are left out.
    var activeSegment: SkipSegment? {
        guard let session else { return nil }
        return session.segments?.value?.first { $0.fit != .uncertain && $0.range.contains(session.position) }
    }

    func tracks(_ kind: TrackKind) -> [MediaTrack] {
        session?.tracks.filter { $0.id.kind == kind } ?? []
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
