import Foundation
import Testing

struct CoreLibraryWireTests {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func encoded(_ action: CoreAction, to field: CoreField?) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(DispatchRequest.core(action, to: field)))
    }

    // The literals are the ones core/src/lib.rs parses as core actions.
    @Test func libraryActionsHaveTheShapesCoreParses() throws {
        let show = MetaPreview(
            media: MediaID("tt0944947").require(), type: .series, name: Redacted("Game of Thrones"),
            poster: URL(string: "https://images.example/poster.jpg"), posterShape: .poster,
            background: nil, logo: nil, releaseInfo: Redacted("2011–2019"), description: Redacted("Left out.")
        )

        #expect(try encoded(.load(.libraryWithFilters(LibraryRequest(LibraryFilter(type: nil, sort: .recentlyWatched)))), to: .library) == json(#"""
        {"field":"library","action":{"action":"Load","args":{"model":"LibraryWithFilters","args":{"request":{"type":null,"sort":"lastwatched"}}}}}
        """#))
        #expect(try encoded(.load(.libraryWithFilters(LibraryRequest(LibraryFilter(type: .series, sort: .unwatchedFirst)))), to: .library) == json(#"""
        {"field":"library","action":{"action":"Load","args":{"model":"LibraryWithFilters","args":{"request":{"type":"series","sort":"notwatched"}}}}}
        """#))
        #expect(try encoded(.library(.loadNextPage), to: .library) == json(#"""
        {"field":"library","action":{"action":"LibraryWithFilters","args":{"action":"LoadNextPage"}}}
        """#))
        #expect(try encoded(.unload, to: .calendar) == json(#"{"field":"calendar","action":{"action":"Unload"}}"#))
        #expect(try encoded(.load(.calendar), to: .calendar) == json(#"""
        {"field":"calendar","action":{"action":"Load","args":{"model":"Calendar","args":null}}}
        """#))
        #expect(try encoded(.ctx(.addToLibrary(show)), to: nil) == json(#"""
        {"field":null,"action":{"action":"Ctx","args":{"action":"AddToLibrary","args":{
            "id":"tt0944947","type":"series","name":"Game of Thrones","poster":"https://images.example/poster.jpg","posterShape":"poster"
        }}}}
        """#))
        #expect(try encoded(.ctx(.removeFromLibrary(id: "tt0944947")), to: nil) == json(#"""
        {"field":null,"action":{"action":"Ctx","args":{"action":"RemoveFromLibrary","args":"tt0944947"}}}
        """#))
    }

    @Test func ratingActionsHaveTheShapesCoreParses() throws {
        #expect(try encoded(.metaDetails(.rate(.liked)), to: .metaDetails) == json(#"""
        {"field":"meta_details","action":{"action":"MetaDetails","args":{"action":"Rate","args":"liked"}}}
        """#))
        #expect(try encoded(.metaDetails(.rate(nil)), to: .metaDetails) == json(#"""
        {"field":"meta_details","action":{"action":"MetaDetails","args":{"action":"Rate","args":null}}}
        """#))
    }

    @Test func libraryStateReadsTypesPagesAndMembership() throws {
        let state = try JSONDecoder().decode(LibraryState.self, from: Data(#"""
        {
            "selected": {"request": {"type": null, "sort": "name", "page": 1}},
            "selectable": {
                "types": [
                    {"type": null, "selected": true, "request": {"type": null, "sort": "name", "page": 1}},
                    {"type": "movie", "selected": false, "request": {"type": "movie", "sort": "name", "page": 1}}
                ],
                "sorts": [],
                "next_page": {"request": {"type": null, "sort": "name", "page": 2}}
            },
            "catalog": [{
                "_id": "tt0111161", "name": "The Shawshank Redemption", "type": "movie", "poster": null,
                "posterShape": "poster", "removed": false, "temp": false, "_ctime": null, "_mtime": "2026-10-01T10:00:00Z",
                "state": {"timeOffset": 0, "duration": 0, "video_id": null, "timesWatched": 0},
                "behaviorHints": {}
            }]
        }
        """#.utf8))

        #expect(state.selected?.request == LibraryRequest(LibraryFilter(type: nil, sort: .name)))
        #expect(state.selectable.types.map(\.type) == [nil, "movie"])
        #expect(state.selectable.nextPage != nil)
        #expect(state.catalog.map(\.isInLibrary) == [true])
    }

    @Test func upcomingEpisodesStartAtTheGivenTimeEarliestFirstAndOnce() throws {
        let start = try Date("2026-10-19T00:00:00Z", strategy: .iso8601)
        let show = #"""
        {
            "id": "tt0944947", "type": "series", "name": "Game of Thrones", "poster": "https://images.example/poster.jpg",
            "posterShape": "poster", "background": null, "logo": null,
            "videos": [
                {"id": "tt0944947:8:2", "title": "Later", "released": "2026-10-26T01:00:00Z", "season": 8, "episode": 2},
                {"id": "tt0944947:8:1", "title": "Tonight", "released": "2026-10-19T20:00:00.000Z", "season": 8, "episode": 1},
                {"id": "tt0944947:7:7", "title": "Yesterday", "released": "2026-10-18T20:00:00Z", "season": 7, "episode": 7},
                {"id": "trailer", "title": "Not an episode", "released": "2026-10-20T20:00:00Z"}
            ]
        }
        """#
        let state = try JSONDecoder().decode(CalendarState.self, from: Data(#"""
        {
            "selected": {"month": 10, "year": 2026},
            "metaItems": [
                {"request": \#(request), "content": {"type": "Ready", "content": [\#(show)]}},
                {"request": \#(request), "content": {"type": "Ready", "content": [\#(show)]}},
                {"request": \#(request), "content": {"type": "Err", "content": {"type": "EmptyContent"}}}
            ]
        }
        """#.utf8))

        let episodes = try #require(state.upcomingEpisodes(from: start)?.value)

        #expect(episodes.map(\.video.rawValue) == ["tt0944947:8:1", "tt0944947:8:2"])
        #expect(episodes.map(\.name.rawValue) == ["Tonight", "Later"])
        #expect(episodes.first?.show.name.rawValue == "Game of Thrones")
        #expect(episodes.first?.released == (try Date("2026-10-19T20:00:00Z", strategy: .iso8601)))
    }

    @Test func upcomingEpisodesWaitForEveryAddonAndFailOnlyWhenAllFailed() throws {
        let start = try Date("2026-10-19T00:00:00Z", strategy: .iso8601)
        func state(_ contents: [String], selected: String = #"{"month": 10, "year": 2026}"#) throws -> CalendarState {
            let items = contents.map { #"{"request": \#(request), "content": \#($0)}"# }.joined(separator: ",")
            return try JSONDecoder().decode(CalendarState.self, from: Data(#"{"selected": \#(selected), "metaItems": [\#(items)]}"#.utf8))
        }
        let failed = #"{"type": "Err", "content": {"type": "Other", "content": "offline"}}"#

        #expect(try state([], selected: "null").upcomingEpisodes(from: start) == nil)
        #expect(try state([]).upcomingEpisodes(from: start) == .loaded([]))
        #expect(try state([#"{"type": "Ready", "content": []}"#, #"{"type": "Loading"}"#]).upcomingEpisodes(from: start) == .loading)
        #expect(try state([#"{"type": "Ready", "content": []}"#, failed]).upcomingEpisodes(from: start) == .loaded([]))
        #expect(try state([failed]).upcomingEpisodes(from: start) == .failed(.addonFailed(reason: #"{"content":"offline","type":"Other"}"#)))
    }

    private let request = #"""
    {"base": "https://v3-cinemeta.strem.io/manifest.json", "path": {"resource": "catalog", "type": "series", "id": "calendar-videos", "extra": [["calendarVideosIds", "tt0944947"]]}}
    """#
}
