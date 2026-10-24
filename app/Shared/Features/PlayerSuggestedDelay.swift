import Foundation

/// The subtitle delay that best lines a track's cues up with where people speak.
extension PlayerFeature {
    /// What a suggestion needs before it is trusted.
    enum SuggestionEvidence {
        /// Furthest a suggestion moves the subtitles from their file's times, either way: as far as
        /// a delay goes. A file from another release can be off by a recap's length.
        static let reach = SubtitleDelay.limit
        /// How far past `reach` delays are tried, so a better fit just beyond it is seen and no
        /// lesser one inside it is offered instead.
        static let lookBeyond = Duration.seconds(4)
        /// Audio heard where the cues are, so a few lines cannot decide it.
        static let minimumHeard = Duration.seconds(60)
        static let minimumCues = 10
        /// Of the audio heard, at least this much speech and this much quiet.
        static let minimumSpeech = Duration.seconds(5)
        /// How much better speech and cues must agree at the best delay than at a typical one, as a
        /// correlation from -1 to 1. Films talk in scenes, so most delays agree somewhat.
        static let minimumLift = 0.15
        /// How much of that lift the best delay must keep over any delay off its hill.
        static let minimumMargin = 0.4
        /// How close to an agreement counts as as good, so noise does not split a hill or a top.
        static let tie = 0.01
    }

    /// The delay, within `SuggestionEvidence.reach` of the file's timing and to a frame's precision,
    /// at which `cues` show while `speech` has people speaking and not while it is quiet. Nil unless
    /// the evidence is clear: enough audio heard where the cues are, enough cues, speech and quiet,
    /// and one delay that agrees far better than most and clearly better than any other away from it.
    static func suggestedDelay(speech: SpeechActivity, cues: [TimedCue]) -> SubtitleDelay? {
        let frame = SpeechActivity.frameDuration
        let reach = Int(SuggestionEvidence.reach / frame)
        let searched = Int((SuggestionEvidence.reach + SuggestionEvidence.lookBeyond) / frame)
        // Frames are indexed from `searched` before the speech to `searched` after it, so under a
        // delay of k frames the speech at index i lines up with the cues at index i - k.
        let origin = speech.firstFrame - searched
        let length = speech.frames.count + 2 * searched
        var shows = [Bool](repeating: false, count: length)
        var cueCount = 0
        for cue in cues {
            let lower = max(firstFrame(from: cue.range.lowerBound) - origin, 0)
            let upper = min(firstFrame(from: cue.range.upperBound) - origin, length)
            guard lower < upper else { continue }
            cueCount += 1
            for index in lower ..< upper { shows[index] = true }
        }
        let runs = runs(of: shows)
        guard cueCount >= SuggestionEvidence.minimumCues, let first = runs.first, let last = runs.last else { return nil }
        let cued = first.lowerBound ..< last.upperBound

        // Running totals over the frames heard while the track has cues: how many, and speech
        // less quiet, so any stretch's sums take two lookups.
        var heard = [0]
        var speaking = [0]
        heard.reserveCapacity(length + 1)
        speaking.reserveCapacity(length + 1)
        for index in 0 ..< length {
            let offset = index - searched
            let sound = cued.contains(index) && speech.frames.indices.contains(offset) ? speech.frames[offset] : .unheard
            heard.append(heard[index] + (sound == .unheard ? 0 : 1))
            speaking.append(speaking[index] + (sound == .speech ? 1 : sound == .quiet ? -1 : 0))
        }
        let count = heard[length]
        let speechTotal = speaking[length]
        let speechFrames = (count + speechTotal) / 2
        let minimumSpeech = Int(SuggestionEvidence.minimumSpeech / frame)
        guard count >= Int(SuggestionEvidence.minimumHeard / frame),
              speechFrames >= minimumSpeech, count - speechFrames >= minimumSpeech else { return nil }

        // A cue counts +1 where it shows and -1 elsewhere, so each sum is twice its part over the
        // cue runs, moved by the delay, less its whole.
        let agreement = (-searched ... searched).map { shift in
            var together = -speechTotal
            var shown = -count
            for run in runs {
                let lower = min(max(run.lowerBound + shift, 0), length)
                let upper = min(max(run.upperBound + shift, 0), length)
                together += 2 * (speaking[upper] - speaking[lower])
                shown += 2 * (heard[upper] - heard[lower])
            }
            return correlation(count: count, together: together, speech: speechTotal, cues: shown)
        }
        guard let peak = agreement.indices.max(by: { agreement[$0] < agreement[$1] }) else { return nil }
        let hill = hill(of: agreement, around: peak)
        let rival = agreement.indices.filter { !hill.contains($0) }.map { agreement[$0] }.max() ?? -1
        let shift = middle(of: agreement, around: peak) - searched
        let lift = agreement[peak] - agreement.sorted()[agreement.count / 2]
        guard abs(shift) <= reach,
              lift >= SuggestionEvidence.minimumLift,
              agreement[peak] - rival >= lift * SuggestionEvidence.minimumMargin else { return nil }
        return SubtitleDelay(clamping: frame * shift)
    }

    /// The stretches of `shows` that are true.
    private static func runs(of shows: [Bool]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        for (index, showing) in shows.enumerated() {
            switch (showing, start) {
            case (true, nil): start = index
            case (false, let begun?):
                runs.append(begun ..< index)
                start = nil
            case (true, _?), (false, nil): break
            }
        }
        if let start { runs.append(start ..< shows.count) }
        return runs
    }

    /// The first frame whose middle lies at or after `time`.
    private static func firstFrame(from time: Duration) -> Int {
        Int((time / SpeechActivity.frameDuration - 0.5).rounded(.up))
    }

    /// Pearson's correlation of two series of `count` values of +1 or -1, from the sum of their
    /// products and the sum of each.
    private static func correlation(count: Int, together: Int, speech: Int, cues: Int) -> Double {
        let squared = Double(count * count)
        let spread = (squared - Double(speech * speech)) * (squared - Double(cues * cues))
        guard spread > 0 else { return 0 }
        return (Double(count * together) - Double(speech * cues)) / spread.squareRoot()
    }

    /// The delays around `peak` that agree less the further they lie from it.
    private static func hill(of agreement: [Double], around peak: Int) -> ClosedRange<Int> {
        var first = peak
        var last = peak
        while first > agreement.startIndex, agreement[first - 1] <= agreement[first] + SuggestionEvidence.tie { first -= 1 }
        while last < agreement.endIndex - 1, agreement[last + 1] <= agreement[last] + SuggestionEvidence.tie { last += 1 }
        return first ... last
    }

    /// The middle of the delays around `peak` that agree about as well as it does. A line shows a
    /// little before people start and after they stop, so a few delays fit it equally.
    private static func middle(of agreement: [Double], around peak: Int) -> Int {
        let floor = agreement[peak] - SuggestionEvidence.tie
        var first = peak
        var last = peak
        while first > agreement.startIndex, agreement[first - 1] >= floor { first -= 1 }
        while last < agreement.endIndex - 1, agreement[last + 1] >= floor { last += 1 }
        return (first + last) / 2
    }
}
