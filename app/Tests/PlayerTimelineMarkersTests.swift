import Foundation
import Testing

struct PlayerTimelineMarkersTests {
    private let chapters = [
        Chapter(id: Chapter.ID(number: 0), title: Redacted("Opening"), start: .zero),
        Chapter(id: Chapter.ID(number: 1), title: Redacted("The Heist"), start: .seconds(600)),
        Chapter(id: Chapter.ID(number: 2), title: Redacted("Escape"), start: .seconds(1_800)),
    ]

    private func segment(_ kind: SegmentKind, _ range: Range<Duration>, fit: SegmentFit = .matched) -> SkipSegment {
        SkipSegment(kind: kind, range: range, fit: fit, confidence: 1)
    }

    /// Playing a 40 minute stream with `chapters`.
    private func playing() -> PlayerFeature.State {
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        _ = PlayerFeature.reduce(&state, .loadStarted(Fixture.candidate(), Fixture.load))
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .loaded))
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .duration(.seconds(2_400))))
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .chapters(chapters)))
        return state
    }

    @Test func chaptersBreakTheTimelineWhereEachAfterTheFirstBegins() {
        #expect(playing().session?.timelineMarkers.chapterStarts == [0.25, 0.75])
    }

    @Test func offeredSegmentsTintTheirStretchOfTheTimeline() {
        var state = playing()
        let recap = segment(.recap, .zero..<(.seconds(60)))
        let intro = segment(.intro, .seconds(120)..<(.seconds(240)))
        let credits = segment(.outro, .seconds(2_280)..<(.seconds(2_400)), fit: .uncertain)
        _ = PlayerFeature.reduce(&state, .segmentsFound(Fixture.movie, .success([recap, intro, credits])))
        #expect(state.session?.timelineMarkers.skippable == [0..<0.025, 0.05..<0.1])
    }

    @Test func nothingIsMarkedUntilTheDurationIsKnown() {
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        _ = PlayerFeature.reduce(&state, .loadStarted(Fixture.candidate(), Fixture.load))
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .chapters(chapters)))
        #expect(state.session?.timelineMarkers == PlayerFeature.TimelineMarkers.none)
    }

    @Test func theCurrentChapterIsTheLastToHaveStarted() {
        var state = playing()
        #expect(state.session?.currentChapter == chapters[0])
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .position(.seconds(600))))
        #expect(state.session?.currentChapter == chapters[1])
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .position(.seconds(1_799))))
        #expect(state.session?.currentChapter == chapters[1])
    }

    @Test func aScanNamesTheChapterItHasReached() {
        var state = playing()
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .position(.seconds(1_790))))
        _ = PlayerFeature.reduce(&state, .timeline(.hold(.forward)))
        for _ in 0..<20 {
            _ = PlayerFeature.reduce(&state, .timeline(.tick))
        }
        #expect(state.session?.position == .seconds(1_790))
        #expect(state.session?.currentChapter == chapters[2])
    }

    @Test func aStreamWithoutChaptersHasNoCurrentChapter() {
        var state = playing()
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .chapters([])))
        #expect(state.session?.currentChapter == nil)
        #expect(state.session?.timelineMarkers.chapterStarts == [])
    }

    @Test func choosingAChapterPlaysFromItsStart() {
        var state = playing()
        #expect(PlayerFeature.reduce(&state, .timeline(.chapter(chapters[2].id))) == [.seekTo(.seconds(1_800))])
        _ = PlayerFeature.reduce(&state, .timeline(.hold(.forward)))
        #expect(PlayerFeature.reduce(&state, .timeline(.chapter(chapters[1].id))) == [.setPaused(false), .seekTo(.seconds(600))])
        #expect(state.session?.scan == nil)
        #expect(PlayerFeature.reduce(&state, .timeline(.chapter(Chapter.ID(number: 9)))).isEmpty)
    }
}
