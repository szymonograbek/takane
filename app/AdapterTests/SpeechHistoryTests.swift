import Foundation
import Testing

struct SpeechHistoryTests {
    private static let rate = SpeechHistory.sampleRate

    /// `seconds` of a sine at `frequency` and `decibels` below full scale, or silence at nil.
    private static func tone(_ frequency: Double?, decibels: Double = -20, seconds: Double, from start: Double = 0) -> [Float] {
        let amplitude = pow(10, decibels / 20) * 2.squareRoot()
        return (0 ..< Int(seconds * rate)).map { index in
            guard let frequency else { return 0 }
            return Float(amplitude * sin(2 * .pi * frequency * (start + Double(index) / rate)))
        }
    }

    /// Plays `samples` from `start` in buffers of 1024, as the engine's tap delivers them.
    private static func play(_ samples: [Float], from start: Double, into history: inout SpeechHistory, continuing: Bool = false) {
        var offset = 0
        while offset < samples.count {
            let end = min(offset + 1024, samples.count)
            history.hear(Array(samples[offset ..< end]), from: start + Double(offset) / rate, continuing: continuing || offset > 0)
            offset = end
        }
    }

    private static func spans(_ activity: SpeechActivity) -> String {
        activity.frames.map { frame in
            switch frame {
            case .unheard: "."
            case .quiet: "_"
            case .speech: "S"
            }
        }.joined()
    }

    @Test func aVoiceInTheBandIsSpeechAndAHumIsNot() {
        var history = SpeechHistory()
        // Five times: 1 s of a 1 kHz voice over a 50 Hz hum, then 1 s of the hum alone.
        var samples: [Float] = []
        for second in 0 ..< 10 {
            let hum = Self.tone(50, decibels: -12, seconds: 1, from: Double(second))
            let voice = Self.tone(second.isMultiple(of: 2) ? 1_000 : nil, seconds: 1, from: Double(second))
            samples += zip(hum, voice).map { $0 + $1 }
        }
        Self.play(samples, from: 0, into: &history)
        let heard = Self.spans(history.activity(in: .zero ..< .seconds(10)))
        let expected = (0 ..< 5).map { _ in String(repeating: "S", count: 10) + String(repeating: "_", count: 10) }.joined()
        // The filter takes a frame to settle at each edge, and the last frame waits for more audio.
        #expect(heard.count == 100)
        #expect(zip(heard, expected).filter { $0 != $1 }.count <= 10)
        #expect(heard.hasPrefix("SSSSSSSS"))
    }

    @Test func framesFollowTheStreamsTime() {
        var history = SpeechHistory()
        Self.play(Self.tone(nil, seconds: 1) + Self.tone(1_000, seconds: 1) + Self.tone(nil, seconds: 1), from: 100, into: &history)
        let activity = history.activity(in: .seconds(99) ..< .seconds(103))
        #expect(activity.firstFrame == 990)
        let heard = Self.spans(activity)
        #expect(heard.hasPrefix(String(repeating: ".", count: 10) + "__________"))
        #expect(heard.dropFirst(21).hasPrefix("SSSSSSSS"))
        #expect(heard.hasSuffix("."))
    }

    @Test func speechHeardOnTheSourceClockLinesUpWithThePosition() {
        var history = SpeechHistory()
        Self.play(Self.tone(nil, seconds: 1) + Self.tone(1_000, seconds: 1) + Self.tone(nil, seconds: 1), from: 100, into: &history)
        var clock = SourceClock()
        _ = clock.read(position: 5, source: 15)
        _ = clock.read(position: 5.25, source: 15.25)
        let activity = history.activity(in: .seconds(89) ..< .seconds(93), on: clock)
        #expect(activity.firstFrame == 890)
        #expect(activity.frames == history.activity(in: .seconds(99) ..< .seconds(103)).frames)
        #expect(activity.frames[20] == .speech)
    }

    @Test func oneSteadySoundHoldsNoSpeech() {
        var history = SpeechHistory()
        Self.play(Self.tone(1_000, seconds: 5), from: 0, into: &history)
        #expect(!Self.spans(history.activity(in: .zero ..< .seconds(5))).contains("S"))
    }

    @Test func shortPausesStayWithinSpeech() {
        var history = SpeechHistory()
        let samples = Self.tone(nil, seconds: 2) + Self.tone(1_000, seconds: 1) + Self.tone(nil, seconds: 0.2)
            + Self.tone(1_000, seconds: 1) + Self.tone(nil, seconds: 2)
        Self.play(samples, from: 0, into: &history)
        let heard = Self.spans(history.activity(in: .zero ..< .seconds(6)))
        #expect(heard.dropFirst(21).hasPrefix(String(repeating: "S", count: 20)))
    }

    @Test func aSeekStartsAfresh() {
        var history = SpeechHistory()
        Self.play(Self.tone(1_000, seconds: 1), from: 0, into: &history)
        Self.play(Self.tone(nil, seconds: 1), from: 60, into: &history)
        Self.play(Self.tone(nil, seconds: 1), from: 61, into: &history, continuing: true)
        let early = Self.spans(history.activity(in: .zero ..< .seconds(1)))
        let late = Self.spans(history.activity(in: .seconds(60) ..< .seconds(62)))
        #expect(!early.contains("."))
        #expect(late.dropLast().allSatisfy { $0 == "_" })
    }
}
