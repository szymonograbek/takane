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
            "streamState": null
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

    @Test func noAnswerUntilCoreHasOneForThisEpisode() throws {
        #expect(try player(playing: "tt0944947:1:1", introOutro: nil).skipSegments(for: Fixture.episode, within: stream) == nil)
        let otherEpisode = try player(playing: "tt0944947:1:2", introOutro: #"{"intro": null, "outro": 2880000}"#)
        #expect(otherEpisode.skipSegments(for: Fixture.episode, within: stream) == nil)
    }
}
