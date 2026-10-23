import SwiftUI

/// Where people speak, moved so `playhead` is in the middle: a block for each stretch of speech and
/// a thin line where the audio played without it. Nothing marks audio not heard yet.
struct SpeechTrack: View {
    let speech: SpeechActivity
    let playhead: Duration

    var body: some View {
        Canvas { context, size in
            let scale = size.width / (2 * (PlayerFeature.alignmentWindow / .seconds(1)))
            let origin = size.width / 2 - (playhead / .seconds(1)) * scale
            for run in runs {
                let x = origin + (run.range.lowerBound / .seconds(1)) * scale
                let width = ((run.range.upperBound - run.range.lowerBound) / .seconds(1)) * scale
                switch run.sound {
                case .speech:
                    let block = CGRect(x: x, y: 0, width: width, height: size.height)
                    context.fill(Path(roundedRect: block, cornerRadius: Metrics.cornerRadius / 2), with: .color(Palette.speech))
                case .quiet:
                    let line = CGRect(x: x, y: (size.height - Metrics.heardLineHeight) / 2, width: width, height: Metrics.heardLineHeight)
                    context.fill(Path(line), with: .color(Palette.heard))
                case .unheard:
                    break
                }
            }
        }
        .frame(height: Metrics.timingLaneHeight)
        .mask { LaneFade() }
    }

    /// The frames, joined into stretches of one sound each.
    private var runs: [(sound: SpeechActivity.Frame, range: Range<Duration>)] {
        var runs: [(sound: SpeechActivity.Frame, range: Range<Duration>)] = []
        for (offset, sound) in speech.frames.enumerated() {
            let start = SpeechActivity.frameDuration * (speech.firstFrame + offset)
            let end = start + SpeechActivity.frameDuration
            if let last = runs.last, last.sound == sound {
                runs[runs.count - 1].range = last.range.lowerBound ..< end
            } else {
                runs.append((sound, start ..< end))
            }
        }
        return runs
    }
}

/// Fades a lane out at both ends.
struct LaneFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0), .init(color: .black, location: Metrics.timingLaneFade),
                .init(color: .black, location: 1 - Metrics.timingLaneFade), .init(color: .clear, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }
}
