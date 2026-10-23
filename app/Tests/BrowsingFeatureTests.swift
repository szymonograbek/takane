import Foundation
import Testing

struct BrowsingFeatureTests {
    private let text = SearchText("twin peaks").require()

    private func genre(_ name: String) -> Genre {
        Genre(name).require()
    }

    @Test func detailsKeepThePreviewUntilTheyLoad() {
        let preview = Fixture.preview("tt0098936", type: .series)
        var state = DetailsFeature.State.loading(preview)
        _ = DetailsFeature.reduce(&state, .loaded(MediaID("tt0111161").require(), .failure(.notFound)))
        #expect(state == .loading(preview))
        _ = DetailsFeature.reduce(&state, .loaded(preview.media, .failure(.notFound)))
        #expect(state == .failed(preview, .notFound))
        #expect(DetailsFeature.reduce(&state, .retry) == [.load(preview)])
    }

    @Test func watchedMarksAreSetOnlyOnTheLoadedTitleAndTheirResultArrivesAsAChange() {
        let show = Fixture.preview("tt0944947", type: .series)
        let episode = PlayableID("tt0944947:1:1").require()
        let unwatched = Fixture.details(show)
        var state = DetailsFeature.State.loading(show)
        #expect(DetailsFeature.reduce(&state, .setWatched(.video(episode), true)).isEmpty)
        _ = DetailsFeature.reduce(&state, .loaded(show.media, .success(unwatched)))

        #expect(DetailsFeature.reduce(&state, .setWatched(.video(episode), true)) == [.setWatched(.video(episode), true)])
        #expect(DetailsFeature.reduce(&state, .setWatched(.season(show.media, 2), false)) == [.setWatched(.season(show.media, 2), false)])
        #expect(DetailsFeature.reduce(&state, .setWatched(.title(MediaID("tt0111161").require()), true)).isEmpty)
        #expect(state == .loaded(unwatched))

        let otherTitle = Fixture.details(Fixture.preview("tt0111161"), isWatched: true)
        _ = DetailsFeature.reduce(&state, .changed(otherTitle))
        #expect(state == .loaded(unwatched))
        let watched = Fixture.details(show, isWatched: true)
        _ = DetailsFeature.reduce(&state, .changed(watched))
        #expect(state == .loaded(watched))
    }

    @Test func libraryMembershipIsSetOnlyOnceTheTitleLoadedAndArrivesAsAChange() {
        let show = Fixture.preview("tt0944947", type: .series)
        let loaded = Fixture.details(Fixture.preview("tt0944947", type: .series, background: URL(filePath: "/wide.jpg")))
        var state = DetailsFeature.State.loading(show)
        #expect(DetailsFeature.reduce(&state, .setInLibrary(true)).isEmpty)
        _ = DetailsFeature.reduce(&state, .loaded(show.media, .success(loaded)))

        #expect(DetailsFeature.reduce(&state, .setInLibrary(true)) == [.setInLibrary(loaded.preview, true)])
        let added = Fixture.details(loaded.preview, isInLibrary: true)
        _ = DetailsFeature.reduce(&state, .changed(added))
        #expect(state == .loaded(added))
        #expect(DetailsFeature.reduce(&state, .setInLibrary(false)) == [.setInLibrary(loaded.preview, false)])
    }

    @Test func ratingIsSentOnlyForALoadedTitleTheProviderRates() {
        let movie = Fixture.preview("tt0111161")
        var state = DetailsFeature.State.loading(movie)
        #expect(DetailsFeature.reduce(&state, .rate(.liked)).isEmpty)
        _ = DetailsFeature.reduce(&state, .loaded(movie.media, .success(Fixture.details(movie))))

        #expect(DetailsFeature.reduce(&state, .rate(.liked)) == [.rate(movie.media, .liked)])
        _ = DetailsFeature.reduce(&state, .changed(Fixture.details(movie, rating: .rated(.liked))))
        #expect(DetailsFeature.reduce(&state, .rate(nil)) == [.rate(movie.media, nil)])
        _ = DetailsFeature.reduce(&state, .changed(Fixture.details(movie, rating: .failed)))
        #expect(DetailsFeature.reduce(&state, .rate(.loved)) == [.rate(movie.media, .loved)])

        _ = DetailsFeature.reduce(&state, .changed(Fixture.details(movie, rating: .unavailable)))
        #expect(DetailsFeature.reduce(&state, .rate(.liked)).isEmpty)
    }

    @Test func ratingIsIgnoredWhenTheTitleFailedToLoad() {
        let movie = Fixture.preview("tt0111161")
        var state = DetailsFeature.State.failed(movie, .notFound)
        #expect(DetailsFeature.reduce(&state, .rate(.liked)).isEmpty)
    }

    @Test func seasonsListSpecialsLastAndPlayStartsAtTheFirstEpisode() {
        let videos = ["tt1:0:1", "tt1:2:1", "tt1:1:2", "tt1:1:1"].map { id in
            let playable = PlayableID(id).require()
            guard case .episode(_, let season, let episode) = playable else { fatalError("fixture is an episode") }
            return Video(
                playable: playable, name: Redacted(id), season: season, episode: episode,
                released: nil, thumbnail: nil, overview: nil, isWatched: false
            )
        }
        let details = Fixture.details(Fixture.preview("tt1", type: .series), videos: videos)
        #expect(details.seasons == [1, 2, 0])
        #expect(details.videos.episodes(in: 1).map(\.playable.rawValue) == ["tt1:1:1", "tt1:1:2"])
        #expect(details.firstPlayable == PlayableID("tt1:1:1"))
    }

    @Test func playStartsALiveChannelItself() {
        let details = Fixture.details(Fixture.preview("fox-sports", type: .liveTV))
        #expect(details.firstPlayable == Fixture.channel)
    }

    @Test func searchDropsResultsForAnOlderQuery() {
        var state = SearchFeature.State()
        #expect(SearchFeature.reduce(&state, .queryChanged(text)) == [.search(text)])
        _ = SearchFeature.reduce(&state, .resultsChanged(.rows(SearchText("twin").require(), [])))
        #expect(state.query == .searching(text, results: nil))
        _ = SearchFeature.reduce(&state, .resultsChanged(.rows(text, [])))
        #expect(state.query == .searching(text, results: .rows(text, [])))
        #expect(SearchFeature.reduce(&state, .queryChanged(text)).isEmpty)
        _ = SearchFeature.reduce(&state, .queryChanged(nil))
        #expect(state.query == .empty)
    }

    @Test func recentSearchesLeaveOutTheStepsOfTypingAnotherAndRepeats() {
        var state = SearchFeature.State()
        let history = ["breaking ba", "breaking bad", "Twin Peaks", "bre", "twin peaks", "dune"].map { SearchText($0).require() }
        _ = SearchFeature.reduce(&state, .recentSearchesChanged(history))
        #expect(state.recentSearches?.map(\.rawValue) == ["breaking bad", "Twin Peaks", "dune"])
    }

    @Test func suggestionsAreAFewRecentSearchesThatContinueTheQuery() {
        var state = SearchFeature.State()
        let history = ["Breaking Bad", "The Bear", "Better Call Saul", "bones", "Bluey", "Blade Runner"].map { SearchText($0).require() }
        _ = SearchFeature.reduce(&state, .recentSearchesChanged(history))
        #expect(state.suggestions.isEmpty)

        _ = SearchFeature.reduce(&state, .queryChanged(SearchText("b")))
        #expect(state.suggestions == [
            SearchSuggestion(search: history[0], typed: "B", completion: "reaking Bad"),
            SearchSuggestion(search: history[2], typed: "B", completion: "etter Call Saul"),
            SearchSuggestion(search: history[3], typed: "b", completion: "ones"),
            SearchSuggestion(search: history[4], typed: "B", completion: "luey"),
        ])
        _ = SearchFeature.reduce(&state, .queryChanged(SearchText("breaking bad")))
        #expect(state.suggestions.isEmpty)
    }

    @Test func genresListOneCatalogPerTypeAndShowWithRecentSearchesBeforeTyping() {
        let popularMovies = CatalogGenres(catalog: CatalogID(addon: Fixture.manifest, type: .movie, id: Redacted("top")), genres: [genre("Action")])
        let featuredMovies = CatalogGenres(catalog: CatalogID(addon: Fixture.manifest, type: .movie, id: Redacted("imdbRating")), genres: [genre("Drama")])
        let popularSeries = CatalogGenres(catalog: CatalogID(addon: Fixture.manifest, type: .series, id: Redacted("top")), genres: [genre("Comedy")])
        var state = SearchFeature.State()
        #expect(state.browse == .waiting)

        _ = SearchFeature.reduce(&state, .genresChanged([popularMovies, featuredMovies, popularSeries]))
        #expect(state.genres == [popularMovies, popularSeries])
        #expect(state.browse == .offers(recentSearches: [], genres: [popularMovies, popularSeries]))

        _ = SearchFeature.reduce(&state, .recentSearchesChanged([text]))
        #expect(state.browse == .offers(recentSearches: [text], genres: [popularMovies, popularSeries]))

        _ = SearchFeature.reduce(&state, .genresChanged([]))
        _ = SearchFeature.reduce(&state, .recentSearchesChanged([]))
        #expect(state.browse == .nothing)
    }

    @Test func genreTitlesAnswerOnlyTheirFilterAndRetryWhenFailedOrEmpty() {
        let catalog = CatalogID(addon: Fixture.manifest, type: .movie, id: Redacted("top"))
        let action = GenreFilter(catalog: catalog, genre: genre("Action"))
        let drama = GenreFilter(catalog: catalog, genre: genre("Drama"))
        let preview = Fixture.preview("tt0111161")
        var state = GenreFeature.State.loading(action)

        #expect(GenreFeature.reduce(&state, .retry).isEmpty)
        _ = GenreFeature.reduce(&state, .titlesChanged(drama, .loaded([preview])))
        #expect(state == .loading(action))
        _ = GenreFeature.reduce(&state, .titlesChanged(action, .failed(.addonFailed(reason: "offline"))))
        #expect(state == .failed(action, .addonFailed(reason: "offline")))
        #expect(GenreFeature.reduce(&state, .retry) == [.load(action)])
        #expect(state == .loading(action))

        _ = GenreFeature.reduce(&state, .titlesChanged(action, .loaded([])))
        #expect(GenreFeature.reduce(&state, .retry) == [.load(action)])
        _ = GenreFeature.reduce(&state, .titlesChanged(action, .loaded([preview])))
        #expect(state == .loaded(action, [preview]))
        #expect(GenreFeature.reduce(&state, .retry).isEmpty)
    }

    @Test func recentSearchesAreClearedOnlyBeforeAnythingIsTyped() {
        var state = SearchFeature.State()
        _ = SearchFeature.reduce(&state, .recentSearchesChanged([]))
        #expect(SearchFeature.reduce(&state, .clearRecentSearches).isEmpty)
        _ = SearchFeature.reduce(&state, .recentSearchesChanged([text]))
        #expect(SearchFeature.reduce(&state, .clearRecentSearches) == [.clearRecentSearches])
        _ = SearchFeature.reduce(&state, .queryChanged(text))
        #expect(SearchFeature.reduce(&state, .clearRecentSearches).isEmpty)
        #expect(state.recentSearches == [text])
    }

    @Test func onlyRemovableAddonsAreRemoved() {
        let official = InstalledAddon(manifestURL: Fixture.otherManifest, name: Redacted("Cinemeta"), version: "3", isRemovable: false, isEnabled: true)
        let debrid = InstalledAddon(manifestURL: Fixture.manifest, name: Redacted("Debrid"), version: "1", isRemovable: true, isEnabled: true)
        var state = AddonsFeature.State(installed: [official, debrid])
        #expect(AddonsFeature.reduce(&state, .uninstall(official.manifestURL)).isEmpty)
        #expect(AddonsFeature.reduce(&state, .uninstall(debrid.manifestURL)) == [.uninstall(debrid.manifestURL)])
        _ = AddonsFeature.reduce(&state, .uninstallFinished(debrid.manifestURL, .failure(.rejected(reason: "offline"))))
        #expect(state.change == .failed(debrid.manifestURL, .rejected(reason: "offline")))
    }
}
