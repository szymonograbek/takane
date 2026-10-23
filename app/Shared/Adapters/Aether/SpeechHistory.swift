import Accelerate
import Foundation

/// How loud the voice band (300 Hz to 3.4 kHz) was in each `SpeechActivity` frame of the audio
/// heard, for the last `capacity` frames, read back as speech and quiet.
///
/// A frame is speech when it stands `rise` above the quietest frame within `reach` of it: voices
/// rise and fall with each syllable, while hum, wind and score hold steady. Loud music and effects
/// still read as speech now and then. A suggestion weighs minutes of frames against the cues, so
/// they blur it less than they would decide it.
struct SpeechHistory {
    /// A frame's sum of squared samples so far, and how many.
    private struct Partial {
        let frame: Int
        let energy: Float
        let samples: Int
    }

    static let sampleRate = 48_000.0
    /// Ten minutes.
    static let capacity = 6_000
    /// Quieter than this, in decibels below full scale, is never speech.
    static let silence: Float = -55
    /// How far either side of a frame its quietest neighbor is looked for, in frames.
    static let reach = 10
    /// How many decibels above that neighbor a frame must be to be speech.
    static let rise: Float = 8
    /// Gaps of speech this short, in frames, are breaths within it.
    static let breath = 2

    private static let samplesPerFrame = Int(sampleRate * (SpeechActivity.frameDuration / .seconds(1)))

    /// Loudness in decibels below full scale, by frame number.
    private var levels: [Int: Float] = [:]
    private var newest = 0
    private var band = SpeechHistory.voiceBand()
    /// The frame being summed.
    private var partial: Partial?

    /// Adds mono `samples` at `sampleRate`, the first at `start` seconds of the stream's time.
    /// Not `continuing` the last ones, they start afresh.
    mutating func hear(_ samples: [Float], from start: Double, continuing: Bool) {
        if !continuing {
            finish()
            band = Self.voiceBand()
            partial = nil
        }
        guard let filtered = band?.apply(input: samples) else { return }
        let first = Int((start * Self.sampleRate).rounded(.down))
        var offset = 0
        while offset < filtered.count {
            let sample = first + offset
            let frame = Int((Double(sample) / Double(Self.samplesPerFrame)).rounded(.down))
            let count = min((frame + 1) * Self.samplesPerFrame - sample, filtered.count - offset)
            let energy = vDSP.sumOfSquares(filtered[offset ..< offset + count])
            if let partial, partial.frame == frame {
                self.partial = Partial(frame: frame, energy: partial.energy + energy, samples: partial.samples + count)
            } else {
                finish()
                partial = Partial(frame: frame, energy: energy, samples: count)
            }
            offset += count
        }
    }

    /// The speech in `range`, from what was heard of it.
    func activity(in range: Range<Duration>) -> SpeechActivity {
        let first = SpeechActivity.frame(containing: range.lowerBound)
        let end = max(SpeechActivity.frame(containing: range.upperBound - .nanoseconds(1)) + 1, first)
        let heard = (first ..< end).map { levels[$0] }
        let frames = heard.indices.map { index -> SpeechActivity.Frame in
            guard let level = heard[index] else { return .unheard }
            var floor = level
            for neighbor in heard[max(index - Self.reach, 0) ... min(index + Self.reach, heard.count - 1)] {
                if let neighbor, neighbor < floor { floor = neighbor }
            }
            return level > max(floor + Self.rise, Self.silence) ? .speech : .quiet
        }
        return SpeechActivity(firstFrame: first, frames: Self.closingBreaths(frames))
    }

    /// Ends the frame being summed, keeping it when enough of it was heard.
    private mutating func finish() {
        guard let partial, partial.samples >= Self.samplesPerFrame / 2 else { return }
        levels[partial.frame] = 10 * log10(partial.energy / Float(partial.samples) + 1e-10)
        newest = partial.frame
        if levels.count > Self.capacity * 11 / 10 {
            levels = levels.filter { abs($0.key - newest) < Self.capacity }
        }
    }

    /// `frames` with quiet gaps of up to `breath` frames between speech filled in.
    private static func closingBreaths(_ frames: [SpeechActivity.Frame]) -> [SpeechActivity.Frame] {
        var closed = frames
        var lastSpeech: Int?
        for (index, frame) in frames.enumerated() {
            switch frame {
            case .speech:
                if let lastSpeech, index - lastSpeech - 1 <= breath {
                    for gap in lastSpeech + 1 ..< index { closed[gap] = .speech }
                }
                lastSpeech = index
            case .unheard:
                lastSpeech = nil
            case .quiet:
                break
            }
        }
        return closed
    }

    /// A 300 Hz high-pass then a 3.4 kHz low-pass, each a Butterworth biquad.
    private static func voiceBand() -> vDSP.Biquad<Float>? {
        vDSP.Biquad(
            coefficients: biquad(highPass: true, at: 300) + biquad(highPass: false, at: 3_400),
            channelCount: 1, sectionCount: 2, ofType: Float.self
        )
    }

    /// One section's b0, b1, b2, a1 and a2, from the Audio EQ Cookbook.
    private static func biquad(highPass: Bool, at frequency: Double) -> [Double] {
        let omega = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(omega) / (2 * 0.5.squareRoot())
        let cosine = cos(omega)
        let scale = 1 + alpha
        let middle = highPass ? -(1 + cosine) : 1 - cosine
        let outer = abs(middle) / 2
        return [outer / scale, middle / scale, outer / scale, -2 * cosine / scale, (1 - alpha) / scale]
    }
}
