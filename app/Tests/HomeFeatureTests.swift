import Foundation
import Testing

struct HomeFeatureTests {
    private func row(_ id: String, items: Remote<[MetaPreview], CatalogError>, canLoadMore: Bool = true) -> CatalogRow {
        CatalogRow(
            id: CatalogID(addon: Fixture.manifest, type: .movie, id: id), addonName: "Cinemeta", name: id,
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

    @Test func resumingNeedsTheSameVideo() {
        let item = Fixture.continueWatching(video: Fixture.episode, offset: .seconds(600))
        let state = HomeFeature.State(continueWatching: [item])
        #expect(state.resumePosition(for: Fixture.episode) == .seconds(600))
        #expect(state.resumePosition(for: PlayableID("tt0944947:1:2").require()) == nil)
    }
}
