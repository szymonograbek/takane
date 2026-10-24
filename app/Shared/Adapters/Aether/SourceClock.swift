import Foundation

/// How far the engine's source clock runs ahead of the playback position. Subtitle cues and the
/// audio tap are stamped on the source clock, the stream's own timestamps, while the position
/// starts at zero. The two differ where a stream's timestamps do not start at zero (an MPEG-TS
/// file, a software session anchored on its first sample) and, on remote HLS, by the lead over
/// the picture the engine measures, which it updates as it plays.
///
/// The offset is read off the clock as it ticks. Around a seek the source clock can stay on the
/// old frame while the position moves, so a reading counts only once the next one agrees with it.
struct SourceClock: Equatable {
    /// How far apart two readings may be and still agree, in seconds: rounding, not movement.
    static let agreement = 0.001

    /// Source time minus position, in seconds.
    private(set) var offset = 0.0
    private var lastReading: Double?

    /// Takes the position and source time of one tick, read together. Returns whether `offset` changed.
    mutating func read(position: Double, source: Double) -> Bool {
        let reading = source - position
        defer { lastReading = reading }
        guard let lastReading, abs(reading - lastReading) < Self.agreement, abs(reading - offset) >= Self.agreement else {
            return false
        }
        offset = reading
        return true
    }

    /// The position at which the source clock reads `seconds`.
    func position(ofSource seconds: Double) -> Duration {
        .seconds(seconds - offset)
    }
}
