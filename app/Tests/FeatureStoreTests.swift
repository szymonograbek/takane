import QuartzCore
import Testing

@MainActor
private final class FakeEngine: PlaybackEngine {
    let surface = CAMetalLayer()
    let events: AsyncStream<PlaybackEvent>
    let emit: AsyncStream<PlaybackEvent>.Continuation
    private(set) var commands: [String] = []

    init() {
        (events, emit) = AsyncStream.makeStream(of: PlaybackEvent.self)
    }

    func load(_ source: PlaybackSource) { commands.append("load \(source.url.lastPathComponent)") }
    func setPaused(_ paused: Bool) { commands.append("paused \(paused)") }
    func seek(by offset: Duration) { commands.append("seek \(offset)") }
    func stop() { commands.append("stop") }
    func diagnostics() -> [String: String] { [:] }
    func snapshot() async -> CGImage? { nil }
}

private final class FakeTracker: PlaybackTracker {
    let reports = AsyncStream<String>.makeStream()

    func begin(_ candidate: StreamCandidate) { reports.continuation.yield("begin \(candidate.filename ?? "")") }
    func progress(_ position: Duration, of duration: Duration) { reports.continuation.yield("progress \(position)") }
    func paused(_ paused: Bool) { reports.continuation.yield("paused \(paused)") }
    func ended() { reports.continuation.yield("ended") }
    func stop() { reports.continuation.yield("stop") }
}

@MainActor
struct FeatureStoreTests {
    private struct TimedOut: Error {}

    @Test func runsEffectsAndFeedsEngineEventsBack() async throws {
        let engine = FakeEngine()
        let tracker = FakeTracker()
        let store = FeatureStore<PlayerFeature>(
            .idle,
            dependencies: PlayerFeature.Dependencies(engine: engine, tracker: tracker),
            start: [.listen]
        )
        store.send(.open(Fixture.candidate()))
        engine.emit.yield(.duration(.seconds(60)))
        engine.emit.yield(.loaded)
        engine.emit.yield(.position(.seconds(2)))
        let session = try await store.until(timeout: .seconds(2), onTimeout: TimedOut()) { state in
            state.session.map { $0.position == .seconds(2) ? .done($0) : .pending } ?? .pending
        }
        #expect(session.phase == .playing)
        #expect(engine.commands == ["load movie.mkv", "paused false"])
        var reports = tracker.reports.stream.makeAsyncIterator()
        #expect(await reports.next() == "begin movie.mkv")
        #expect(await reports.next() == "progress 2.0 seconds")
    }

    @Test func untilTimesOut() async {
        let store = FeatureStore<StreamsFeature>(.idle, dependencies: StreamsFeature.Dependencies(streams: NoStreams()))
        await #expect(throws: TimedOut.self) {
            try await store.until(timeout: .milliseconds(50), onTimeout: TimedOut()) { _ in Probe<Void, TimedOut>.pending }
        }
    }
}

private struct NoStreams: StreamService {
    func streams(for item: PlayableID) -> AsyncStream<StreamResults> {
        AsyncStream { $0.finish() }
    }
}
