import Foundation

/// Plays one stream at a time, keeps the tracker informed of progress and offers the next episode.
enum PlayerFeature: Feature {
    struct Dependencies: Sendable {
        let engine: any PlaybackEngine
        let tracker: any PlaybackTracker
        let skipSegments: @Sendable (SkipSegmentSource) -> any SkipSegmentService
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
        var title = Redacted("")
        var phase = Phase.opening
        var position = Duration.zero
        /// Zero until the engine knows it.
        var duration = Duration.zero
        var isBuffering = false
        var videoSize: VideoSize?
        var decoder: String?
        /// The whole second last reported to the tracker.
        var reportedSecond: Int64?
        var tracks: [MediaTrack] = []
        /// What each add-on offers for this stream, apart from the stream's own tracks.
        var addonSubtitles: [SubtitleSource] = []
        var speed = PlaybackSpeed.normal
        /// How far back and forward skip, from the preferences.
        var seekStep = SeekStep.defaults
        /// The subtitles visible now.
        var subtitles: [SubtitleCue] = []
        /// How far the subtitles are moved from their file's times.
        var subtitleDelay = SubtitleDelay.zero
        /// The selected subtitle track's cues, for timing them.
        var cueTimeline: [TimedCue] = []
        /// In order of start.
        var chapters: [Chapter] = []
        /// What was heard of the speech, for the timing strip and the delay it suggests.
        var speech = SpeechTiming()
        /// Parts of the stream the viewer may skip, found once the duration is known.
        var segments: Remote<[SkipSegment], SkipSegmentError>?
        /// Where to find `segments`, from the preferences.
        var skipSegmentSource = SkipSegmentSource.defaults
        var scan: Scan?
        var streak: StepStreak?
        var restore = Restore.awaiting
        var subtitleLanguages: PreferredLanguages?
        /// False once the viewer or remembered choices picked the subtitles, which the app then leaves alone.
        var picksSubtitles = true
        /// When to offer the next episode and whether it plays by itself, from the preferences.
        var upNextBehavior = UpNextBehavior.defaults
        var upNext = UpNextOffer.notFound
    }

    enum State: Equatable, Sendable {
        case idle
        case active(Session)
        case failed(StreamCandidate, PlaybackError)
    }

    enum Event: Sendable {
        /// Plays `candidate` from `start`, such as a saved position, labelled `title`.
        case open(StreamCandidate, from: Duration = .zero, title: Redacted<String> = Redacted(""))
        case togglePause
        /// Skips one `seekStep` in `direction`.
        case jump(Direction)
        case timeline(TimelineEvent)
        case select(MediaTrack.ID)
        case chooseSubtitles(SubtitleChoice)
        case setSpeed(PlaybackSpeed)
        case subtitleTiming(SubtitleTimingEvent)
        case skip(SkipSegment)
        case stop
        case engine(PlaybackEvent)
        case segmentsFound(PlayableID, Result<[SkipSegment], SkipSegmentError>)
        case subtitlesFound(StreamCandidate, [SubtitleSource])
        case preferencesRead(StreamCandidate, Preferences)
        case remembered(StreamCandidate, TrackChoices)
        case upNext(UpNextEvent)
    }

    enum Report: Equatable, Sendable {
        case progress(Duration, of: Duration)
        case seek(to: Duration, of: Duration)
        case paused(Bool)
        case ended
        /// The viewer chose these tracks and speed.
        case choices(TrackChoices)
        case movedToNext
    }

    enum Effect: Equatable, Sendable {
        /// Feeds engine events back as `.engine`. Start it once, when the store is created.
        case listen
        /// Reads the preferences and starts playback, then follows the add-ons' subtitles and what was
        /// remembered for it until another candidate replaces it.
        case begin(StreamCandidate, PlaybackSource, from: Duration)
        /// Feeds the episode after the candidate back as `.upNext(.found)` until another candidate replaces it.
        case watchUpNext(StreamCandidate)
        case setPaused(Bool)
        case seek(by: Duration)
        case seekTo(Duration)
        /// Sends `.timeline(.tick)` after `scanTickInterval`.
        case scanTick
        case select(MediaTrack.ID)
        case turnOffSubtitles
        case addSubtitles(AddonSubtitle)
        case setSpeed(PlaybackSpeed)
        case setSubtitleDelay(SubtitleDelay)
        case hearSpeech(Bool)
        /// Sends `.subtitleTiming(.heard)` with the speech in the range, once `after` has passed.
        case sampleSpeech(Range<Duration>, after: Duration)
        case findSegments(PlayableID, duration: Duration, from: SkipSegmentSource)
        case stop
        case report(Report)
    }

    static func key(_ effect: Effect) -> AnyHashable? {
        if case .sampleSpeech = effect { return "sampleSpeech" }
        return effect == .scanTick ? "scanTick" : nil
    }

    /// `reduce` without hearing speech, which `reduce` starts and stops around it.
    static func reduceEvent(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state, event) {
        case (_, .open(let candidate, let start, let title)):
            return open(candidate, from: start, title: title, replacing: &state)

        case (.active(let session), .togglePause):
            return update(&state, session) { $0.togglePause() }

        // A live channel plays where its broadcast is: nothing to seek to.
        case (.active(let session), .jump(let direction)) where !session.isLive:
            return update(&state, session) { $0.endScan() + [.seek(by: $0.seekStep.duration * direction.sign)] }

        case (.active(let session), .timeline(let event)) where !session.isLive:
            return update(&state, session) { $0.apply(event) }

        case (.active(let session), .select(let track)):
            return update(&state, session) { $0.select(track) }

        case (.active(let session), .chooseSubtitles(let choice)):
            return update(&state, session) { $0.chooseSubtitles(choice) }

        case (.active(let session), .setSpeed(let speed)):
            return update(&state, session) { $0.setSpeed(speed) }

        case (.active(let session), .subtitleTiming(let event)):
            return update(&state, session) { $0.apply(event) }

        case (.active(let session), .skip(let segment)) where session.segments?.value?.contains(segment) == true:
            return update(&state, session) { $0.endScan() + [.seekTo(segment.range.upperBound)] }

        case (.active(var session), .segmentsFound(let item, let result)) where item == session.candidate.item:
            session.segments = switch result {
            case .success(let segments): .loaded(segments)
            case .failure(let error): .failed(error)
            }
            state = .active(session)
            return []

        case (.active(let session), .subtitlesFound(let candidate, let sources)) where candidate == session.candidate:
            return update(&state, session) { $0.receive(sources) }

        case (.active(let session), .remembered(let candidate, let choices)) where candidate == session.candidate:
            return update(&state, session) { $0.restoreRemembered(choices) }

        case (.active(var session), .preferencesRead(let candidate, let preferences)) where candidate == session.candidate:
            session.read(preferences)
            state = .active(session)
            return []

        case (.active(let session), .upNext(let event)):
            return reduce(event, in: session, replacing: &state)

        case (.active, .stop), (.failed, .stop):
            state = .idle
            return [.stop]

        case (.active(var session), .engine(let event)):
            let effects = session.apply(event)
            switch event {
            case .failed(let reason): state = .failed(session.candidate, .failed(reason: reason))
            case .stopped where session.phase != .opening: state = .idle
            default: state = .active(session)
            }
            return event == .ended ? effects + autoplayNext(after: session, replacing: &state) : effects

        case (.idle, .togglePause), (.idle, .jump), (.idle, .stop), (.idle, .engine), (.idle, .subtitleTiming),
             (.failed, .togglePause), (.failed, .jump), (.failed, .engine), (.failed, .subtitleTiming),
             (.idle, .select), (.idle, .chooseSubtitles), (.idle, .setSpeed), (.idle, .skip), (.idle, .segmentsFound),
             (.failed, .select), (.failed, .chooseSubtitles), (.failed, .setSpeed), (.failed, .skip), (.failed, .segmentsFound),
             (.idle, .subtitlesFound), (.failed, .subtitlesFound), (.idle, .timeline), (.failed, .timeline),
             (.idle, .preferencesRead), (.failed, .preferencesRead), (.idle, .remembered), (.failed, .remembered),
             (.idle, .upNext), (.failed, .upNext), (.active, .jump), (.active, .timeline),
             (.active, .segmentsFound), (.active, .subtitlesFound), (.active, .preferencesRead), (.active, .skip), (.active, .remembered):
            return []
        }
    }

    /// Starts a session for `candidate`, or fails it when it cannot play, stopping what played before.
    static func open(_ candidate: StreamCandidate, from start: Duration, title: Redacted<String>, replacing state: inout State) -> [Effect] {
        switch candidate.playability {
        case .playable(let source):
            state = .active(Session(candidate: candidate, title: title))
            return [.begin(candidate, source, from: start), .watchUpNext(candidate)]
        case .unsupported(let kind):
            let wasActive = state.session != nil
            state = .failed(candidate, .unsupported(kind: kind))
            return wasActive ? [.stop] : []
        }
    }

    /// Runs `change` on the active session and keeps the result.
    private static func update(_ state: inout State, _ session: Session, _ change: (inout Session) -> [Effect]) -> [Effect] {
        var session = session
        let effects = change(&session)
        state = .active(session)
        return effects
    }
}

extension PlayerFeature {
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
            var updates = dependencies.preferences.preferences().makeAsyncIterator()
            let preferences = await updates.next()
            if let preferences { send(.preferencesRead(candidate, preferences)) }
            tracker.begin(candidate)
            engine.load(source, from: start, languages: preferences?.languages ?? .streamDefaults)
            await follow(candidate, playing: source, dependencies, send)
        case .watchUpNext(let candidate):
            for await next in tracker.upNext(after: candidate) {
                send(.upNext(.found(candidate, next)))
            }
        case .setPaused(let paused):
            engine.setPaused(paused)
        case .seek(let offset):
            engine.seek(by: offset)
        case .seekTo(let position):
            engine.seek(to: position)
        case .scanTick:
            guard (try? await Task.sleep(for: scanTickInterval)) != nil else { return }
            send(.timeline(.tick))
        case .select(let track):
            engine.select(track)
        case .turnOffSubtitles:
            engine.turnOffSubtitles()
        case .addSubtitles(let subtitle):
            engine.addSubtitles(subtitle.url, from: subtitle.source, title: subtitle.label?.rawValue ?? subtitle.language, language: subtitle.language)
        case .setSpeed(let speed):
            engine.setSpeed(speed)
        case .setSubtitleDelay(let delay):
            engine.setSubtitleDelay(delay)
        case .hearSpeech(let hearing): engine.hearSpeech(hearing)
        case .sampleSpeech(let range, let delay):
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            send(.subtitleTiming(.heard(engine.speechActivity(in: range))))
        case .findSegments(let item, let duration, let source):
            do {
                let found = try await dependencies.skipSegments(source).segments(for: item, duration: duration)
                send(.segmentsFound(item, .success(found.segments)))
            } catch {
                send(.segmentsFound(item, .failure(error)))
            }
        case .stop:
            engine.stop()
            tracker.stop()
        case .report(let report):
            deliver(report, to: tracker)
        }
    }

    @MainActor
    private static func deliver(_ report: Report, to tracker: any PlaybackTracker) {
        switch report {
        case .progress(let position, let duration): tracker.progress(position, of: duration)
        case .seek(let position, let duration): tracker.seek(to: position, of: duration)
        case .paused(let paused): tracker.paused(paused)
        case .ended: tracker.ended()
        case .choices(let choices): tracker.remember(choices)
        case .movedToNext: tracker.movedToNext()
        }
    }
}

extension PlayerFeature.Session {
    /// Takes the seek step, subtitle languages, up next behavior and skip segment source from the preferences.
    mutating func read(_ preferences: Preferences) {
        seekStep = preferences.seekStep
        subtitleLanguages = preferences.languages.subtitles
        upNextBehavior = preferences.upNext
        skipSegmentSource = preferences.skipSegmentSource
    }

    var isLive: Bool {
        if case .liveChannel = candidate.item { true } else { false }
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

    func tracks(_ kind: TrackKind) -> [MediaTrack] {
        session?.tracks.filter { $0.id.kind == kind } ?? []
    }
}
