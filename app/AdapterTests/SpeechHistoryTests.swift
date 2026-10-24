import Foundation
import Testing

struct SpeechHistoryTests {
    private static func spans(_ activity: SpeechActivity) -> String {
        activity.frames.map { frame in
            switch frame {
            case .unheard: "."
            case .quiet: "_"
            case .speech: "S"
            }
        }.joined()
    }

    /// Half-second windows every 100 ms from `start` to `end` seconds, as the classifier hears
    /// them, sure of speech by `confidence` at each window's start.
    private static func hear(from start: Double, to end: Double, into history: inout SpeechHistory, confidence: (Double) -> Double) {
        var time = start
        while time + 0.5 <= end + 1e-9 {
            history.record(time ..< time + 0.5, confidence: confidence(time))
            time += 0.1
        }
    }

    @Test func framesTheWindowsAreSureOfAreSpeech() {
        var history = SpeechHistory()
        // Speech from 2 s to 4 s.
        Self.hear(from: 0, to: 6, into: &history) { (1.75 ..< 4).contains($0) ? 0.9 : 0.1 }
        let heard = Self.spans(history.activity(in: .seconds(0.7) ..< .seconds(6.7), on: SourceClock()))
        #expect(heard.count == 60)
        #expect(heard.hasPrefix(String(repeating: "_", count: 15)))
        #expect(heard.dropFirst(20).hasPrefix(String(repeating: "S", count: 20)))
        #expect(heard.dropFirst(45).allSatisfy { $0 == "_" })
    }

    @Test func speechShowsWhereInSyncLinesSit() {
        var history = SpeechHistory()
        Self.hear(from: 100, to: 101, into: &history) { _ in 0.9 }
        let activity = history.activity(in: .seconds(100) ..< .seconds(102), on: SourceClock())
        let lag = Int(SpeechHistory.subtitleLag / SpeechActivity.frameDuration)
        #expect(Self.spans(activity) == String(repeating: ".", count: lag) + String(repeating: "S", count: 10) + String(repeating: ".", count: 10 - lag))
    }

    @Test func speechHeardOnTheSourceClockLinesUpWithThePosition() {
        var history = SpeechHistory()
        Self.hear(from: 100, to: 101, into: &history) { _ in 0.9 }
        var clock = SourceClock()
        _ = clock.read(position: 5, source: 15)
        _ = clock.read(position: 5.25, source: 15.25)
        let onPosition = history.activity(in: .seconds(90) ..< .seconds(92), on: clock)
        let onSource = history.activity(in: .seconds(100) ..< .seconds(102), on: SourceClock())
        #expect(onPosition.firstFrame == 900)
        #expect(onPosition.frames == onSource.frames)
    }

    @Test func audioNotHeardIsUnheard() {
        var history = SpeechHistory()
        Self.hear(from: 10, to: 11, into: &history) { _ in 0.1 }
        #expect(Self.spans(history.activity(in: .zero ..< .seconds(2), on: SourceClock())) == String(repeating: ".", count: 20))
    }
}
