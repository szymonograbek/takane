import CoreGraphics
import Foundation
import os
import Testing

@MainActor
private final class FakeEngine: PlaybackEngine {
    let events: AsyncStream<PlaybackEvent>
    let emit: AsyncStream<PlaybackEvent>.Continuation
    private(set) var commands: [String] = []

    init() {
        (events, emit) = AsyncStream.makeStream(of: PlaybackEvent.self)
    }

    func load(_ source: PlaybackSource, from start: Duration, languages: TrackLanguages) {
        commands.append("load \(source.url.rawValue.lastPathComponent) from \(start) \(languages.subtitles?.primary.code ?? "-")")
    }
    func setPaused(_ paused: Bool) { commands.append("paused \(paused)") }
    func seek(by offset: Duration) { commands.append("seek \(offset)") }
    func seek(to position: Duration) { commands.append("seek to \(position)") }
    func select(_ track: MediaTrack.ID) { commands.append("select \(track.number)") }
    func turnOffSubtitles() { commands.append("subtitles off") }
    func addSubtitles(_ file: Redacted<URL>, title: String, language: String) { commands.append("add \(file.rawValue.lastPathComponent)") }
    func setSpeed(_ speed: PlaybackSpeed) { commands.append("speed \(speed.rawValue)") }
    func stop() { commands.append("stop") }
    func diagnostics() -> [String: String] { [:] }
    func snapshot() async -> CGImage? { nil }
}

private final class FakeTracker: PlaybackTracker {
    let reports = AsyncStream<String>.makeStream()

    func begin(_ candidate: StreamCandidate) { reports.continuation.yield("begin \(candidate.filename?.rawValue ?? "")") }
    func progress(_ position: Duration, of duration: Duration) { reports.continuation.yield("progress \(position)") }
    func seek(to position: Duration, of duration: Duration) { reports.continuation.yield("seek \(position)") }
    func paused(_ paused: Bool) { reports.continuation.yield("paused \(paused)") }
    func ended() { reports.continuation.yield("ended") }
    func movedToNext() { reports.continuation.yield("moved to next") }
    func stop() { reports.continuation.yield("stop") }
    func remember(_ choices: TrackChoices) { reports.continuation.yield("remember \(choices)") }
    func remembered(for candidate: StreamCandidate, playing source: PlaybackSource) -> AsyncStream<TrackChoices> {
        AsyncStream { $0.finish() }
    }
    func upNext(after candidate: StreamCandidate) -> AsyncStream<UpNext?> { AsyncStream { $0.finish() } }
}

@MainActor
struct FeatureStoreTests {
    private struct TimedOut: Error {}

    @Test func runsEffectsAndFeedsEngineEventsBack() async throws {
        let engine = FakeEngine()
        let tracker = FakeTracker()
        let store = FeatureStore<PlayerFeature>(
            .idle,
            dependencies: PlayerFeature.Dependencies(
                engine: engine, tracker: tracker, skipSegments: { _ in NoSegments() }, preferences: FixedPreferences(),
                subtitles: OneSubtitleSource()
            ),
            start: [.listen]
        )
        store.send(.open(Fixture.candidate(), from: .seconds(30)))
        engine.emit.yield(.duration(.seconds(60)))
        engine.emit.yield(.loaded)
        engine.emit.yield(.position(.seconds(2)))
        let session = try await store.until(timeout: .seconds(2), onTimeout: TimedOut()) { state in
            state.session.map { $0.position == .seconds(2) && !$0.addonSubtitles.isEmpty ? .done($0) : .pending } ?? .pending
        }
        #expect(session.phase == .playing)
        #expect(session.seekStep == .thirty)
        #expect(session.addonSubtitles == [OneSubtitleSource.source])
        #expect(engine.commands == ["load movie.mkv from 30.0 seconds pol"])
        var reports = tracker.reports.stream.makeAsyncIterator()
        #expect(await reports.next() == "begin movie.mkv")
        #expect(await reports.next() == "progress 2.0 seconds")
    }

    @Test func aNewerSearchCancelsTheOneStillWaiting() async throws {
        let catalog = RecordingCatalog()
        let store = FeatureStore<SearchFeature>(
            SearchFeature.State(), dependencies: SearchFeature.Dependencies(catalog: catalog, settle: .milliseconds(50))
        )
        store.send(.queryChanged(SearchText("tw")))
        store.send(.queryChanged(SearchText("twin")))
        _ = try await store.until(timeout: .seconds(2), onTimeout: TimedOut()) { state in
            if case .searching(_, results: .rows?) = state.query { Probe<Void, TimedOut>.done(()) } else { .pending }
        }
        #expect(catalog.searched.withLock { $0 } == ["twin"])
    }

    @Test func untilTimesOut() async {
        let store = FeatureStore<StreamsFeature>(.idle, dependencies: StreamsFeature.Dependencies(streams: NoStreams(), offers: NoOffers()))
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

private struct NoOffers: WatchOfferService {
    func offers(for title: MediaID) async throws(WatchOfferError) -> [WatchOffer] { [] }
}

private struct OneSubtitleSource: SubtitleService {
    static let source = SubtitleSource(addon: Fixture.manifest, addonName: Redacted("Subtitles"), subtitles: .loaded([]))

    func subtitles(for candidate: StreamCandidate, playing source: PlaybackSource) -> AsyncStream<[SubtitleSource]> {
        AsyncStream { $0.yield([Self.source]) }
    }
}

private struct NoSegments: SkipSegmentService {
    func segments(for item: PlayableID, duration: Duration) async throws(SkipSegmentError) -> SkipSegments {
        SkipSegments(item: item, segments: [], introLengthEstimate: nil)
    }
}

private struct FixedPreferences: PreferencesService {
    func preferences() -> AsyncStream<Preferences> {
        let languages = TrackLanguages(audio: nil, subtitles: PreferredLanguages(primary: Language("pol").require(), fallback: nil))
        let preferences = Preferences(
            languages: languages, subtitleStyle: .defaults, seekStep: .thirty, hidesSpoilers: false, upNext: .defaults, skipSegmentSource: .defaults
        )
        return AsyncStream { $0.yield(preferences) }
    }

    func update(_ preferences: Preferences) throws(PreferencesError) {}
}

private final class RecordingCatalog: CatalogService {
    let searched = OSAllocatedUnfairLock<[String]>(initialState: [])

    func board() -> AsyncStream<Board> { AsyncStream { $0.finish() } }
    func loadMore(_ row: CatalogID) {}
    func details(_ media: MediaID, type: ContentType) async throws(DetailsError) -> TitleDetails { throw .notFound }
    func detailsChanges(_ media: MediaID, type: ContentType) -> AsyncStream<TitleDetails> { AsyncStream { $0.finish() } }
    func recentSearches() -> AsyncStream<[SearchText]> { AsyncStream { $0.finish() } }
    func clearRecentSearches() {}
    func genres() -> AsyncStream<[CatalogGenres]> { AsyncStream { $0.finish() } }
    func titles(_ filter: GenreFilter) -> AsyncStream<Remote<[MetaPreview], CatalogError>> { AsyncStream { $0.finish() } }

    func search(_ text: SearchText) -> AsyncStream<SearchResults> {
        searched.withLock { $0.append(text.rawValue) }
        return AsyncStream { $0.yield(.rows(text, [])) }
    }
}
