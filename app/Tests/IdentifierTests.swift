import Testing

struct IdentifierTests {
    @Test func parsesMoviesAndEpisodes() {
        #expect(PlayableID("tt0111161")?.rawValue == "tt0111161")
        #expect(PlayableID("tt0944947:1:2") == .episode(MediaID("tt0944947").require(), season: 1, episode: 2))
        #expect(PlayableID("tt0944947:1:2")?.media.rawValue == "tt0944947")
    }

    @Test(arguments: ["", "tt1:1", "tt1:a:2", "tt1:1:2:3", "tt 1", "tt1:-1:2"])
    func rejectsMalformedItemIDs(_ text: String) {
        #expect(PlayableID(text) == nil)
    }

    @Test func acceptsOnlyHTTPManifests() {
        #expect(ManifestURL(" https://addon.example/manifest.json ")?.description == "https://addon.example/manifest.json")
        #expect(ManifestURL("ftp://addon.example/manifest.json") == nil)
        #expect(ManifestURL("manifest.json") == nil)
    }

    @Test func trimsSearchTextAndRejectsBlankQueries() {
        #expect(SearchText("  shawshank\n")?.rawValue == "shawshank")
        #expect(SearchText(" \t ") == nil)
    }

    @Test func parsesAddonContentTypes() {
        #expect(ContentType("series") == .series)
        #expect(ContentType("channel")?.rawValue == "channel")
        #expect(ContentType("") == nil)
    }
}
