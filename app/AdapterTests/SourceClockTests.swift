import Foundation
import Testing

struct SourceClockTests {
    /// Whether each reading, in order, changed the offset.
    private func read(_ clock: inout SourceClock, _ ticks: [(position: Double, source: Double)]) -> [Bool] {
        ticks.map { clock.read(position: $0.position, source: $0.source) }
    }

    @Test func cuesStampedOnTheSourceClockLandWhereThePositionShowsThem() {
        var clock = SourceClock()
        #expect(read(&clock, [(0.5, 10.5), (0.75, 10.75)]) == [false, true])
        #expect(clock.offset == 10)
        #expect(clock.position(ofSource: 38) == .seconds(28))
        // A delay measured from the playhead (28.25) to that cue shows it at the source time now.
        #expect(.seconds(28.25) - clock.position(ofSource: 38) == .seconds(38.25 - 38))
    }

    @Test func aSeekLeavingTheSourceClockOnTheOldFrameIsIgnored() {
        var clock = SourceClock()
        #expect(read(&clock, [(20, 30), (20.25, 30.25), (60, 30.25), (60.25, 70.25)]) == [false, true, false, false])
        #expect(clock.offset == 10)
    }

    @Test func aNewOffsetCountsOnceTwoTicksAgree() {
        var clock = SourceClock()
        #expect(read(&clock, [(20, 30), (20.25, 30.25), (20.5, 30), (20.75, 30.25)]) == [false, true, false, true])
        #expect(clock.offset == 9.5)
    }

    @Test func aStreamThatStartsAtZeroNeedsNoMove() {
        var clock = SourceClock()
        #expect(read(&clock, [(3, 3), (3.25, 3.25)]) == [false, false])
        #expect(clock.position(ofSource: 12) == .seconds(12))
    }
}
