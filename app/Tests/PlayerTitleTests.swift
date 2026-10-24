import Foundation
import Testing

struct PlayerTitleTests {
    private let playing = Fixture.candidate(item: PlayableID("tt0903747:5:6").require())

    private func episode(_ season: Int, _ number: Int, isWatched: Bool = false) -> Video {
        Video(
            playable: PlayableID("tt0903747:\(season):\(number)").require(), name: Redacted("Episode \(number)"),
            season: season, episode: number, released: nil, thumbnail: nil, overview: nil, isWatched: isWatched
        )
    }

    private func title(_ videos: [Video]) -> PlayingTitle {
        PlayingTitle(name: Redacted("Breaking Bad"), description: Redacted("A teacher turns."), backdrop: nil, videos: videos, next: nil)
    }

    private func opened(_ candidate: StreamCandidate) -> PlayerFeature.State {
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(candidate))
        _ = PlayerFeature.reduce(&state, .loadStarted(candidate, Fixture.load))
        return state
    }

    @Test func theTitleIsKeptForTheCandidateItAnswers() {
        var state = opened(playing)
        let found = title([episode(5, 6)])
        #expect(PlayerFeature.reduce(&state, .titleFound(Fixture.candidate(index: 3), found)).isEmpty)
        #expect(state.session?.meta == nil)
        _ = PlayerFeature.reduce(&state, .titleFound(playing, found))
        #expect(state.session?.meta == found)
        #expect(state.session?.playingVideo == episode(5, 6))
    }

    @Test func episodesAreThePlayingSeasonInOrder() {
        var state = opened(playing)
        let videos = [episode(5, 7), episode(4, 1, isWatched: true), episode(5, 6), episode(5, 1, isWatched: true)]
        _ = PlayerFeature.reduce(&state, .titleFound(playing, title(videos)))
        #expect(state.session?.seasonEpisodes == [episode(5, 1, isWatched: true), episode(5, 6), episode(5, 7)])
    }

    @Test func aMovieShowsInfoAloneUntilItsFileHasChapters() {
        var state = opened(Fixture.candidate())
        _ = PlayerFeature.reduce(&state, .titleFound(Fixture.candidate(), title([])))
        #expect(state.session?.tabs == [.info])
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .chapters([Chapter(id: Chapter.ID(number: 0), title: Redacted("Chapter 1"), start: .zero)])))
        #expect(state.session?.tabs == [.info, .chapters])
    }

    @Test func aSeriesShowsEpisodesOnceItsSeasonIsKnown() {
        var state = opened(playing)
        #expect(state.session?.tabs == [.info])
        _ = PlayerFeature.reduce(&state, .titleFound(playing, title([episode(4, 1)])))
        #expect(state.session?.tabs == [.info])
        _ = PlayerFeature.reduce(&state, .titleFound(playing, title([episode(5, 6), episode(5, 7)])))
        #expect(state.session?.tabs == [.info, .episodes])
    }
}
