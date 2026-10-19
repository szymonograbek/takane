import Foundation
import Testing

struct BrowsingFeatureTests {
    private let text = SearchText("twin peaks").require()

    @Test func detailsKeepThePreviewUntilTheyLoad() {
        let preview = Fixture.preview("tt0098936", type: .series)
        var state = DetailsFeature.State.loading(preview)
        _ = DetailsFeature.reduce(&state, .loaded(MediaID("tt0111161").require(), .failure(.notFound)))
        #expect(state == .loading(preview))
        _ = DetailsFeature.reduce(&state, .loaded(preview.media, .failure(.notFound)))
        #expect(state == .failed(preview, .notFound))
        #expect(DetailsFeature.reduce(&state, .retry) == [.load(preview)])
    }

    @Test func seasonsListSpecialsLastAndPlayStartsAtTheFirstEpisode() {
        let videos = ["tt1:0:1", "tt1:2:1", "tt1:1:2", "tt1:1:1"].map { id in
            let playable = PlayableID(id).require()
            guard case .episode(_, let season, let episode) = playable else { fatalError("fixture is an episode") }
            return Video(playable: playable, name: id, season: season, episode: episode, released: nil, thumbnail: nil, overview: nil)
        }
        let details = TitleDetails(preview: Fixture.preview("tt1", type: .series), genres: [], runtime: nil, imdbRating: nil, videos: videos)
        #expect(details.seasons == [1, 2, 0])
        #expect(details.episodes(in: 1).map(\.playable.rawValue) == ["tt1:1:1", "tt1:1:2"])
        #expect(details.firstPlayable == PlayableID("tt1:1:1"))
    }

    @Test func searchDropsResultsForAnOlderQuery() {
        var state = SearchFeature.State.empty
        #expect(SearchFeature.reduce(&state, .queryChanged(text)) == [.search(text)])
        _ = SearchFeature.reduce(&state, .resultsChanged(.rows(SearchText("twin").require(), [])))
        #expect(state == .searching(text, results: nil))
        _ = SearchFeature.reduce(&state, .resultsChanged(.rows(text, [])))
        #expect(state == .searching(text, results: .rows(text, [])))
        #expect(SearchFeature.reduce(&state, .queryChanged(text)).isEmpty)
        _ = SearchFeature.reduce(&state, .queryChanged(nil))
        #expect(state == .empty)
    }

    @Test func onlyRemovableAddonsAreRemoved() {
        let official = InstalledAddon(manifestURL: Fixture.otherManifest, name: "Cinemeta", version: "3", isRemovable: false)
        let debrid = InstalledAddon(manifestURL: Fixture.manifest, name: "Debrid", version: "1", isRemovable: true)
        var state = AddonsFeature.State(installed: [official, debrid])
        #expect(AddonsFeature.reduce(&state, .uninstall(official.manifestURL)).isEmpty)
        #expect(AddonsFeature.reduce(&state, .uninstall(debrid.manifestURL)) == [.uninstall(debrid.manifestURL)])
        _ = AddonsFeature.reduce(&state, .uninstallFinished(debrid.manifestURL, .failure(.rejected(reason: "offline"))))
        #expect(state.removal == .failed(debrid.manifestURL, .rejected(reason: "offline")))
    }
}
