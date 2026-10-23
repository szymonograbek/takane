import Foundation
import Testing

struct SuggestedDelayTests {
    /// The same numbers on every run.
    private struct SplitMix: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    private static let frame = SpeechActivity.frameDuration

    /// Lines of dialogue from 1.5 to 4 s long with 0.5 to 5 s between them, over `length`.
    private static func dialogue(_ length: Duration, seed: UInt64 = 1) -> [TimedCue] {
        var random = SplitMix(state: seed)
        var cues: [TimedCue] = []
        var start = Duration.seconds(2)
        while start < length {
            let end = start + .milliseconds(Int64.random(in: 1500 ... 4000, using: &random))
            cues.append(TimedCue(id: TimedCue.ID(number: cues.count), range: start ..< end, text: Redacted("")))
            start = end + .milliseconds(Int64.random(in: 500 ... 5000, using: &random))
        }
        return cues
    }

    /// The speech of `cues` as heard over `length`, when the subtitles need `delay` to match it.
    /// People start a little after a line shows and stop a little before it goes. `flips` of the
    /// frames read wrong, `silent` of the lines have no speech (a sign, a song), and `heard`
    /// picks the frames that played.
    private static func speech(
        of cues: [TimedCue], over length: Duration, delay: Duration,
        flips: Double = 0, silent: Double = 0, seed: UInt64 = 2,
        heard: (Int) -> Bool = { _ in true }
    ) -> SpeechActivity {
        var random = SplitMix(state: seed)
        let spoken = cues.filter { _ in Double.random(in: 0 ..< 1, using: &random) >= silent }
            .map { $0.range.lowerBound + delay + .milliseconds(250) ..< $0.range.upperBound + delay - .milliseconds(250) }
        let frames = (0 ..< Int(length / frame)).map { index -> SpeechActivity.Frame in
            guard heard(index) else { return .unheard }
            let middle = frame * index + frame / 2
            let speaks = spoken.contains { $0.contains(middle) }
            return speaks != (Double.random(in: 0 ..< 1, using: &random) < flips) ? .speech : .quiet
        }
        return SpeechActivity(firstFrame: 0, frames: frames)
    }

    private static func milliseconds(_ delay: SubtitleDelay?) -> Int64? {
        delay.map { Int64(($0.duration / .milliseconds(1)).rounded()) }
    }

    @Test(arguments: [-7300, -2300, -100, 0, 100, 1400, 4000, 9500] as [Int64])
    func findsTheDelayTheSpeechNeeds(_ offset: Int64) {
        let cues = Self.dialogue(.seconds(180))
        let speech = Self.speech(of: cues, over: .seconds(180), delay: .milliseconds(offset))
        #expect(Self.milliseconds(PlayerFeature.suggestedDelay(speech: speech, cues: cues)) == offset)
    }

    @Test(arguments: [-3600, 0, 2000] as [Int64])
    func findsItThroughNoiseAndSilentLines(_ offset: Int64) throws {
        let cues = Self.dialogue(.seconds(180), seed: 7)
        let speech = Self.speech(of: cues, over: .seconds(180), delay: .milliseconds(offset), flips: 0.2, silent: 0.15, seed: 8)
        let found = try #require(Self.milliseconds(PlayerFeature.suggestedDelay(speech: speech, cues: cues)))
        #expect(abs(found - offset) <= 200)
    }

    @Test func weighsOnlyWhatWasHeard() throws {
        let cues = Self.dialogue(.seconds(240))
        // Played in 20 s stretches with 20 s skipped between them.
        let speech = Self.speech(of: cues, over: .seconds(240), delay: .milliseconds(-1200)) { ($0 / 200).isMultiple(of: 2) }
        let found = try #require(Self.milliseconds(PlayerFeature.suggestedDelay(speech: speech, cues: cues)))
        #expect(abs(found + 1200) <= 100)
    }

    @Test func needsAMinuteHeard() {
        let cues = Self.dialogue(.seconds(180))
        let speech = Self.speech(of: cues, over: .seconds(180), delay: .milliseconds(1400)) { $0 < 550 }
        #expect(PlayerFeature.suggestedDelay(speech: speech, cues: cues) == nil)
    }

    @Test func needsTenCues() {
        let cues = Array(Self.dialogue(.seconds(180)).prefix(9))
        let speech = Self.speech(of: cues, over: .seconds(180), delay: .milliseconds(1400))
        #expect(PlayerFeature.suggestedDelay(speech: speech, cues: cues) == nil)
    }

    @Test func needsSpeech() {
        let cues = Self.dialogue(.seconds(180))
        let quiet = SpeechActivity(firstFrame: 0, frames: Array(repeating: .quiet, count: 1800))
        #expect(PlayerFeature.suggestedDelay(speech: quiet, cues: cues) == nil)
    }

    @Test func offersNothingForSpeechUnrelatedToTheCues() {
        let cues = Self.dialogue(.seconds(180), seed: 3)
        let unrelated = Self.speech(of: Self.dialogue(.seconds(180), seed: 4), over: .seconds(180), delay: .zero)
        #expect(PlayerFeature.suggestedDelay(speech: unrelated, cues: cues) == nil)
    }

    @Test func offersNothingBeyondItsReach() {
        let cues = Self.dialogue(.seconds(180))
        let speech = Self.speech(of: cues, over: .seconds(180), delay: .seconds(14))
        #expect(PlayerFeature.suggestedDelay(speech: speech, cues: cues) == nil)
    }

    @Test func readsTheSpeechWhereverItStarts() {
        let cues = Self.dialogue(.seconds(400))
        let whole = Self.speech(of: cues, over: .seconds(400), delay: .milliseconds(800))
        let later = whole.slice(.seconds(200) ..< .seconds(390))
        #expect(later.firstFrame == 2000)
        #expect(Self.milliseconds(PlayerFeature.suggestedDelay(speech: later, cues: cues)) == 800)
    }
}
