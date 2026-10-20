import Testing

struct StreamsFeatureTests {
    private func results(_ item: PlayableID, complete: Bool) -> StreamResults {
        StreamResults(
            item: item,
            sources: [
                StreamSource(addon: Fixture.manifest, addonName: Redacted("Debrid"), candidates: .loaded([Fixture.candidate(), Fixture.candidate(index: 1)])),
                StreamSource(
                    addon: Fixture.otherManifest, addonName: Redacted("Other"), candidates: complete ? .failed(.addonFailed(reason: "500")) : .loading
                ),
            ],
            isComplete: complete
        )
    }

    @Test func showsResultsAsTheyArriveAndCountsWhenComplete() {
        var state = StreamsFeature.State.idle
        #expect(StreamsFeature.reduce(&state, .lookUp(Fixture.movie)) == [.watch(Fixture.movie)])
        #expect(state.message == "Loading…")
        _ = StreamsFeature.reduce(&state, .resultsChanged(results(Fixture.movie, complete: false)))
        #expect(state.loadedSources.map(\.addonName) == [Redacted("Debrid")])
        #expect(state.isLookingUp)
        _ = StreamsFeature.reduce(&state, .resultsChanged(results(Fixture.movie, complete: true)))
        #expect(state.message == "2 streams from 1 add-ons")
        #expect(!state.isLookingUp)
    }

    @Test func dropsResultsForAPreviousLookup() {
        var state = StreamsFeature.State.idle
        _ = StreamsFeature.reduce(&state, .lookUp(Fixture.movie))
        _ = StreamsFeature.reduce(&state, .lookUp(Fixture.episode))
        _ = StreamsFeature.reduce(&state, .resultsChanged(results(Fixture.movie, complete: true)))
        #expect(state == .lookingUp(Fixture.episode, results: nil))
    }
}
