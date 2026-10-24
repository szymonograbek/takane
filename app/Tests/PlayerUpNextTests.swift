import Foundation
import Testing

struct PlayerUpNextTests {
    private let next = UpNext(
        video: PlayableID("tt0944947:1:2").require(), show: Redacted("Game of Thrones"), title: Redacted("The Kingsroad"),
        thumbnail: nil, backdrop: nil, stream: Fixture.candidate(index: 1)
    )
    private let nextStream = Fixture.candidate(index: 1)

    /// The tracker's answer for a title whose next episode is `next`.
    private func title(next: UpNext?) -> PlayingTitle {
        PlayingTitle(name: Redacted("Game of Thrones"), description: nil, backdrop: nil, videos: [], next: next)
    }

    /// Playing `Fixture.candidate()` at `position` of 100 s, with the tracker's answer `next`.
    private func offering(_ next: UpNext?, at position: Duration = .seconds(50), behavior: UpNextBehavior = .defaults) -> PlayerFeature.State {
        var session = PlayerFeature.Session(candidate: Fixture.candidate())
        session.phase = .playing
        session.position = position
        session.duration = .seconds(100)
        session.upNextBehavior = behavior
        var state = PlayerFeature.State.active(session)
        _ = PlayerFeature.reduce(&state, .titleFound(Fixture.candidate(), title(next: next)))
        return state
    }

    @Test func theCardShowsFromTheNoticeBeforeTheEnd() {
        var state = offering(next, at: .seconds(64))
        #expect(state.session?.upNextCard == nil)
        _ = PlayerFeature.reduce(&state, .engine(.position(.seconds(65))))
        #expect(state.session?.upNextCard == next)
        _ = PlayerFeature.reduce(&state, .engine(.position(.seconds(30))))
        #expect(state.session?.upNextCard == nil)
    }

    @Test func noCardWhenTheNoticeIsOffOrNothingFollows() {
        let off = offering(next, at: .seconds(99), behavior: UpNextBehavior(notice: .off, autoplay: true))
        #expect(off.session?.upNextCard == nil)
        let nothing = offering(nil, at: .seconds(99))
        #expect(nothing.session?.upNext == PlayerFeature.UpNextOffer.notFound)
        #expect(nothing.session?.upNextCard == nil)
    }

    @Test func anAnswerForAnotherCandidateIsDropped() {
        var state = offering(nil, at: .seconds(90))
        #expect(PlayerFeature.reduce(&state, .titleFound(Fixture.candidate(index: 2), title(next: next))).isEmpty)
        #expect(state.session?.upNext == PlayerFeature.UpNextOffer.notFound)
    }

    @Test func dismissingHidesTheCardAndStopsAutoplay() {
        var state = offering(next, at: .seconds(90))
        #expect(PlayerFeature.reduce(&state, .upNext(.dismiss)).isEmpty)
        #expect(state.session?.upNextCard == nil)
        _ = PlayerFeature.reduce(&state, .titleFound(Fixture.candidate(), title(next: next)))
        #expect(state.session?.upNext == PlayerFeature.UpNextOffer.dismissed)
        #expect(PlayerFeature.reduce(&state, .upNext(.play)).isEmpty)
        #expect(PlayerFeature.reduce(&state, .engine(.ended)) == [.report(.ended)])
        #expect(state.session?.phase == .ended)
    }

    @Test func playNowReportsTheMoveThenOpensTheNextStream() {
        var state = offering(next, at: .seconds(90))
        #expect(PlayerFeature.reduce(&state, .upNext(.play)) == [
            .report(.movedToNext), .begin(nextStream, Fixture.source, from: .zero), .watchTitle(nextStream),
        ])
        #expect(state.session?.candidate == nextStream)
        #expect(state.session?.title.rawValue == "Game of Thrones · S1 E2")
        #expect(state.session?.upNext == PlayerFeature.UpNextOffer.notFound)
    }

    @Test func withoutAStreamPlayNowLeavesTheChoiceToTheViewer() {
        let unready = UpNext(video: next.video, show: next.show, title: next.title, thumbnail: nil, backdrop: nil, stream: nil)
        var state = offering(unready, at: .seconds(90))
        #expect(PlayerFeature.reduce(&state, .upNext(.play)) == [.report(.movedToNext)])
        #expect(state.session?.candidate == Fixture.candidate())
        #expect(state.session?.upNextCard == nil)

        state = offering(unready)
        #expect(PlayerFeature.reduce(&state, .engine(.ended)) == [.report(.ended)])
        #expect(state.session?.upNextCard == unready)
    }

    @Test func theNextEpisodePlaysByItselfWhenThisOneEnds() {
        var state = offering(next)
        #expect(PlayerFeature.reduce(&state, .engine(.ended)) == [
            .report(.ended), .report(.movedToNext), .begin(nextStream, Fixture.source, from: .zero), .watchTitle(nextStream),
        ])
        #expect(state.session?.candidate == nextStream)
    }

    @Test func withoutAutoplayTheEndKeepsTheCardUp() {
        var state = offering(next, behavior: UpNextBehavior(notice: .defaults, autoplay: false))
        #expect(PlayerFeature.reduce(&state, .engine(.ended)) == [.report(.ended)])
        #expect(state.session?.phase == .ended)
        #expect(state.session?.upNextCard == next)
    }
}
