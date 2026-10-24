import Foundation
import Testing

/// Engine events reach only the session whose load sent them.
struct PlayerLoadTests {
    @Test func eventsOfTheLoadAnotherCandidateReplacedChangeNothing() {
        let next = Fixture.candidate(index: 1)
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        _ = PlayerFeature.reduce(&state, .loadStarted(Fixture.candidate(), Fixture.load))
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .loaded))
        _ = PlayerFeature.reduce(&state, .open(next))
        let opening = state
        for event in [PlaybackEvent.loaded, .ended, .failed(reason: "gone"), .stopped] {
            #expect(PlayerFeature.reduce(&state, .engine(Fixture.load, event)).isEmpty)
        }
        #expect(state == opening)
    }

    @Test func eventsWaitForTheirLoadToStart() {
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .loaded))
        #expect(state.session?.phase == .opening)
        _ = PlayerFeature.reduce(&state, .loadStarted(Fixture.candidate(), Fixture.load))
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .loaded))
        #expect(state.session?.phase == .playing)
    }

    @Test func aReplacedLoadIsNotTheNewOne() {
        let next = Fixture.candidate(index: 1)
        let nextLoad = PlaybackLoad()
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        _ = PlayerFeature.reduce(&state, .loadStarted(Fixture.candidate(), Fixture.load))
        _ = PlayerFeature.reduce(&state, .open(next))
        _ = PlayerFeature.reduce(&state, .loadStarted(next, nextLoad))
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .failed(reason: "gone")))
        _ = PlayerFeature.reduce(&state, .engine(Fixture.load, .stopped))
        _ = PlayerFeature.reduce(&state, .engine(nextLoad, .loaded))
        #expect(state.session?.candidate == next)
        #expect(state.session?.phase == .playing)
    }
}
