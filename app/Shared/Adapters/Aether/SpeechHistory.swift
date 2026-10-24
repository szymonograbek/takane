import AVFoundation
import Foundation
import SoundAnalysis
import Synchronization

/// Where people spoke in the audio heard, as Apple's sound classifier hears it, for the last
/// `capacity` frames of `SpeechActivity`.
///
/// The classifier names what a stretch of audio sounds like (speech, music, laughter…), so voices
/// stand out from a film's score and room sound, which a loudness test reads as speech. It hears
/// overlapping windows; a frame is speech when the windows over it are, on average, sure enough.
struct SpeechHistory {
    /// Ten minutes.
    static let capacity = 6_000
    /// How sure, from 0 to 1, the classifier must be on average over a frame for it to be speech.
    static let threshold = 0.5
    /// How much later than the classifier hears words a subtitle file shows their line. Lines start
    /// and stay up after the words, so in-sync files trail the speech heard by this much (0.6 to
    /// 0.9 s on Breaking Bad and Sintel against their own embedded tracks). Speech is reported this
    /// much later, where in-sync lines sit.
    static let subtitleLag = Duration.milliseconds(700)

    /// The summed speech confidence of the windows over each frame, and how many.
    private var heard: [Int: (confidence: Double, windows: Int)] = [:]
    private var newest = 0

    /// Adds a window of the source clock the classifier was `confidence` sure had speech.
    mutating func record(_ window: Range<Double>, confidence: Double) {
        let frame = SpeechActivity.frameDuration / .seconds(1)
        let first = Int((window.lowerBound / frame).rounded())
        let end = max(Int((window.upperBound / frame).rounded()), first + 1)
        for index in first ..< end {
            let sum = heard[index] ?? (0, 0)
            heard[index] = (sum.confidence + confidence, sum.windows + 1)
        }
        newest = max(newest, end - 1)
        if heard.count > Self.capacity * 11 / 10 {
            heard = heard.filter { abs($0.key - newest) < Self.capacity }
        }
    }

    /// The speech in `range` of positions, from what was heard on the source clock `clock` reads.
    /// Speech is kept a frame at a time, so the clock's offset and the lag round to whole frames.
    func activity(in range: Range<Duration>, on clock: SourceClock) -> SpeechActivity {
        let frame = SpeechActivity.frameDuration / .seconds(1)
        let lead = Int(((clock.offset - Self.subtitleLag / .seconds(1)) / frame).rounded())
        let shift = SpeechActivity.frameDuration * lead
        let lower = range.lowerBound + shift
        let first = SpeechActivity.frame(containing: lower)
        let end = max(SpeechActivity.frame(containing: range.upperBound + shift - .nanoseconds(1)) + 1, first)
        let frames = (first ..< end).map { index -> SpeechActivity.Frame in
            guard let sum = heard[index] else { return .unheard }
            return sum.confidence / Double(sum.windows) >= Self.threshold ? .speech : .quiet
        }
        return SpeechActivity(firstFrame: first - lead, frames: frames)
    }
}

/// Runs Apple's sound classifier over the audio heard, off the main actor, into a `SpeechHistory`
/// that the main actor reads.
actor SpeechListener {
    /// The classifier's shortest window, half a second, heard every frame.
    private static let window = 0.5
    private static let sampleRate = 48_000.0

    /// What the classifier heard, shared with its results observer and with readers.
    nonisolated let history = SpeechStore()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SpeechListener.sampleRate, channels: 1)
    /// The analysis of the audio heard since the last discontinuity.
    private var analysis: Analysis?

    private struct Analysis {
        let analyzer: SNAudioStreamAnalyzer
        /// Kept here because the analyzer does not keep it.
        let observer: SpeechObserver
        /// How many samples it has had.
        var samples: AVAudioFramePosition = 0
    }

    /// Hears mono `samples`, the first at `start` seconds of the source clock. Not `continuing` the
    /// last ones, they start a new analysis.
    func hear(_ samples: [Float], from start: Double, continuing: Bool) {
        guard let format, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() { channel[index] = sample }
        if !continuing || analysis == nil {
            analysis?.analyzer.completeAnalysis()
            analysis = startAnalysis(at: start, format: format)
        }
        guard let current = analysis else { return }
        current.analyzer.analyze(buffer, atAudioFramePosition: current.samples)
        analysis?.samples += AVAudioFramePosition(samples.count)
    }

    private func startAnalysis(at start: Double, format: AVAudioFormat) -> Analysis? {
        let analyzer = SNAudioStreamAnalyzer(format: format)
        let observer = SpeechObserver(history: history, start: start)
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.windowDuration = CMTime(seconds: Self.window, preferredTimescale: CMTimeScale(Self.sampleRate))
            request.overlapFactor = 1 - (SpeechActivity.frameDuration / .seconds(1)) / Self.window
            try analyzer.add(request, withObserver: observer)
        } catch {
            Log.player.error("speech classifier unavailable: \(error)")
            return nil
        }
        return Analysis(analyzer: analyzer, observer: observer)
    }
}

/// A `SpeechHistory` behind a lock: the classifier writes it from its own thread and the main actor
/// reads it.
final class SpeechStore: Sendable {
    private let history = Mutex(SpeechHistory())

    func record(_ window: Range<Double>, confidence: Double) {
        history.withLock { $0.record(window, confidence: confidence) }
    }

    func activity(in range: Range<Duration>, on clock: SourceClock) -> SpeechActivity {
        history.withLock { $0.activity(in: range, on: clock) }
    }
}

/// Records each window the classifier hears into a `SpeechStore`, timed on the source clock from
/// the analysis' `start`.
private final class SpeechObserver: NSObject, SNResultsObserving, Sendable {
    let history: SpeechStore
    let start: Double

    init(history: SpeechStore, start: Double) {
        self.history = history
        self.start = start
    }

    func request(_ request: any SNRequest, didProduce result: any SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let from = start + result.timeRange.start.seconds
        let confidence = result.classification(forIdentifier: "speech")?.confidence ?? 0
        history.record(from ..< from + result.timeRange.duration.seconds, confidence: confidence)
    }

    func request(_ request: any SNRequest, didFailWithError error: any Error) {
        Log.player.error("speech classifier failed: \(error)")
    }
}
