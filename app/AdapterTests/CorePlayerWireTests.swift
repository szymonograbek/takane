import Foundation
import Testing

struct CorePlayerWireTests {
    private let stream = Duration.zero...(.seconds(3_000))

    /// core's player state for an episode, with `introOutro` as core serializes it when given.
    private func player(playing id: String, introOutro: String?) throws -> PlayerState {
        try JSONDecoder().decode(PlayerState.self, from: Data("""
        {
            "selected": {
                "stream": {"url": "https://debrid.example/episode.mkv", "name": "Debrid 1080p"},
                "streamRequest": {
                    "base": "https://addon.example/manifest.json",
                    "path": {"resource": "stream", "type": "series", "id": "\(id)", "extra": []}
                },
                "metaRequest": null,
                "subtitlesPath": null
            },
            "subtitles": [],
            "metaItem": null,
            "nextVideo": null,
            "nextStreams": null,
            "nextStream": null,
            "streamState": null,
            "watchedVideos": []
            \(introOutro.map { #", "introOutro": \#($0)"# } ?? "")
        }
        """.utf8))
    }

    @Test func introOutroBecomesAnIntroAndCreditsToTheEnd() throws {
        let state = try player(playing: "tt0944947:1:1", introOutro: #"{"intro": {"from": 60000, "to": 95500, "duration": null}, "outro": 2880000}"#)

        #expect(state.skipSegments(for: Fixture.episode, within: stream) == SkipSegments(
            item: Fixture.episode,
            segments: [
                SkipSegment(kind: .intro, range: .milliseconds(60_000) ..< .milliseconds(95_500), fit: .matched, confidence: 1),
                SkipSegment(kind: .outro, range: .milliseconds(2_880_000) ..< .seconds(3_000), fit: .matched, confidence: 1),
            ],
            introLengthEstimate: nil
        ))
    }

    @Test func anIntroScaledFromAnotherCutHasAnUnknownFit() throws {
        let state = try player(playing: "tt0944947:1:1", introOutro: #"{"intro": {"from": 60000, "to": 90000, "duration": 31000}, "outro": null}"#)

        #expect(state.skipSegments(for: Fixture.episode, within: stream)?.segments == [
            SkipSegment(kind: .intro, range: .seconds(60) ..< .seconds(90), fit: .unknown, confidence: 1),
        ])
    }

    @Test func noIntroOrOutroIsAnAnswerWithNoSegments() throws {
        let state = try player(playing: "tt0944947:1:1", introOutro: #"{"intro": null, "outro": null}"#)

        #expect(state.skipSegments(for: Fixture.episode, within: stream) == SkipSegments(item: Fixture.episode, segments: [], introLengthEstimate: nil))
    }

    @Test func theSubtitleDelayGoesBackWithTheKeysTheAppLeavesAlone() throws {
        var state = try JSONDecoder().decode(StreamItemState.self, from: Data(#"{"subtitleDelay": -1500, "subtitleSize": 120}"#.utf8))
        #expect(state.subtitleDelay == -1_500)
        state.subtitleDelay = 800
        let sent = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(state))
        #expect(sent == .object(["subtitleDelay": .number(800), "subtitleSize": .number(120)]))
    }

    @Test func subtitlesInSyncLeaveNoDelayForCore() throws {
        var state = try JSONDecoder().decode(StreamItemState.self, from: Data(#"{"subtitleDelay": 800}"#.utf8))
        state.choices = TrackChoices(speed: .normal)
        let sent = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(state))
        #expect(sent == .object(["playbackSpeed": .number(1)]))
    }

    @Test func aDelayGoesToCoreInWholeMilliseconds() {
        var state = StreamItemState()
        state.choices = TrackChoices(subtitleDelay: SubtitleDelay(clamping: .microseconds(1_250_600)))
        #expect(state.subtitleDelay == 1_251)
        state.choices = TrackChoices(subtitleDelay: SubtitleDelay(clamping: .microseconds(-400_400)))
        #expect(state.subtitleDelay == -400)
    }

    @Test func aStoredDelayReadsBackWithinTheLimit() throws {
        let state = try JSONDecoder().decode(StreamItemState.self, from: Data(#"{"subtitleDelay": -45000}"#.utf8))
        #expect(state.choices.subtitleDelay == SubtitleDelay(clamping: .seconds(-30)))
        #expect(StreamItemState().choices.subtitleDelay == .zero)
    }

    @Test func noAnswerUntilCoreHasOneForThisEpisode() throws {
        #expect(try player(playing: "tt0944947:1:1", introOutro: nil).skipSegments(for: Fixture.episode, within: stream) == nil)
        let otherEpisode = try player(playing: "tt0944947:1:2", introOutro: #"{"intro": null, "outro": 2880000}"#)
        #expect(otherEpisode.skipSegments(for: Fixture.episode, within: stream) == nil)
    }

    @Test func theMetaItemListsTheTitlesVideosAndWhichWereWatched() throws {
        let state = try JSONDecoder().decode(PlayerState.self, from: Data("""
        {
            "selected": null,
            "subtitles": [],
            "metaItem": {
                "request": {
                    "base": "https://addon.example/manifest.json",
                    "path": {"resource": "meta", "type": "series", "id": "tt0944947", "extra": []}
                },
                "content": {"type": "Ready", "content": {
                    "id": "tt0944947", "type": "series", "name": "Game of Thrones", "description": "Nine families fight.",
                    "background": null,
                    "videos": [
                        {"id": "tt0944947:1:1", "title": "Winter Is Coming", "season": 1, "episode": 1},
                        {"id": "tt0944947:1:2", "title": "The Kingsroad", "season": 1, "episode": 2}
                    ]
                }}
            },
            "nextVideo": null,
            "nextStreams": null,
            "nextStream": null,
            "streamState": null,
            "watchedVideos": ["tt0944947:1:1"]
        }
        """.utf8))

        let show = try #require(state.metaItem?.content?.readyContent)
        #expect(show.description == "Nine families fight.")
        let videos = show.videos.compactMap { $0.video(watched: state.watchedVideos) }
        #expect(videos.map(\.playable.rawValue) == ["tt0944947:1:1", "tt0944947:1:2"])
        #expect(videos.map(\.isWatched) == [true, false])
    }
}
