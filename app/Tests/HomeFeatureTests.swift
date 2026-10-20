import Foundation
import Testing

struct HomeFeatureTests {
    private func row(_ id: String, items: Remote<[MetaPreview], CatalogError>, canLoadMore: Bool = true) -> CatalogRow {
        CatalogRow(
            id: CatalogID(addon: Fixture.manifest, type: .movie, id: Redacted(id)), addonName: Redacted("Cinemeta"), name: Redacted(id),
            items: items, canLoadMore: canLoadMore
        )
    }

    @Test func theHeroIsTheFirstLoadedTitleWithWideArtwork() {
        let plain = Fixture.preview("tt1", background: nil)
        let wide = Fixture.preview("tt2", background: URL(filePath: "/wide.jpg"))
        let state = HomeFeature.State(board: .rows([row("top", items: .loading), row("popular", items: .loaded([plain, wide]))]))
        #expect(state.featured == wide)
    }

    @Test func moreIsLoadedOnlyForASettledRowThatPages() {
        let loading = row("top", items: .loading)
        let done = row("popular", items: .loaded([Fixture.preview("tt1")]), canLoadMore: false)
        let paging = row("new", items: .loaded([Fixture.preview("tt2")]))
        var state = HomeFeature.State(board: .rows([loading, done, paging]))
        #expect(HomeFeature.reduce(&state, .loadMore(loading.id)).isEmpty)
        #expect(HomeFeature.reduce(&state, .loadMore(done.id)).isEmpty)
        #expect(HomeFeature.reduce(&state, .loadMore(paging.id)) == [.loadMore(paging.id)])
    }

    @Test func onlyAMovieInContinueWatchingIsMarkedWatched() {
        let movie = ContinueWatchingItem(
            media: Fixture.movie.media, type: .movie, name: Redacted("Movie"), poster: nil, background: nil,
            video: Fixture.movie, reason: .partway(offset: .seconds(600), duration: .seconds(6_000))
        )
        let series = Fixture.continueWatching(video: Fixture.episode, offset: .seconds(600))
        var state = HomeFeature.State(continueWatching: [movie, series])
        #expect(HomeFeature.reduce(&state, .markWatched(movie.media)) == [.markWatched(movie.media)])
        #expect(HomeFeature.reduce(&state, .markWatched(series.media)).isEmpty)
        #expect(HomeFeature.reduce(&state, .markWatched(MediaID("tt9999999").require())).isEmpty)
    }

    @Test func resumingNeedsTheSameVideo() {
        let item = Fixture.continueWatching(video: Fixture.episode, offset: .seconds(600))
        let state = HomeFeature.State(continueWatching: [item])
        #expect(state.resumePosition(for: Fixture.episode) == .seconds(600))
        #expect(state.progress(of: item.media) == item)
        #expect(state.resumePosition(for: PlayableID("tt0944947:1:2").require()) == nil)
    }

    @Test func aShowListedForNewEpisodesHasNothingToResume() {
        let item = Fixture.continueWatching(video: Fixture.episode, reason: .newEpisodes(count: 2))
        let state = HomeFeature.State(continueWatching: [item])
        #expect(state.resumePosition(for: Fixture.episode) == nil)
        #expect(state.progress(of: item.media) == nil)
    }
}
