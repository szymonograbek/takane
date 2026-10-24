import SwiftUI

/// Where people speak, moved so `playhead` is in the middle: a block for each stretch of speech, a
/// thin line where the audio played without it, and dots where it has not played yet, such as
/// ahead of the playhead.
struct SpeechTrack: View {
    let speech: SpeechActivity
    let playhead: Duration

    var body: some View {
        Canvas { context, size in
            let scale = size.width / (2 * (PlayerFeature.alignmentWindow / .seconds(1)))
            let origin = size.width / 2 - (playhead / .seconds(1)) * scale
            var unheardFrom: CGFloat = 0
            for run in runs {
                let x = origin + (run.range.lowerBound / .seconds(1)) * scale
                let width = ((run.range.upperBound - run.range.lowerBound) / .seconds(1)) * scale
                switch run.sound {
                case .speech:
                    drawUnheard(in: &context, from: unheardFrom, to: x, height: size.height)
                    unheardFrom = x + width
                    let block = CGRect(x: x, y: 0, width: width, height: size.height)
                    context.fill(Path(roundedRect: block, cornerRadius: Metrics.cornerRadius / 2), with: .color(Palette.speech))
                case .quiet:
                    drawUnheard(in: &context, from: unheardFrom, to: x, height: size.height)
                    unheardFrom = x + width
                    let line = CGRect(x: x, y: (size.height - Metrics.heardLineHeight) / 2, width: width, height: Metrics.heardLineHeight)
                    context.fill(Path(line), with: .color(Palette.heard))
                case .unheard:
                    break
                }
            }
            drawUnheard(in: &context, from: unheardFrom, to: size.width, height: size.height)
        }
        .frame(height: Metrics.timingLaneHeight)
        .mask { LaneFade() }
    }

    /// Dots from `start` to `end`, where the audio has not played.
    private func drawUnheard(in context: inout GraphicsContext, from start: CGFloat, to end: CGFloat, height: CGFloat) {
        guard end > start else { return }
        var line = Path()
        line.move(to: CGPoint(x: start, y: height / 2))
        line.addLine(to: CGPoint(x: end, y: height / 2))
        let style = StrokeStyle(lineWidth: Metrics.heardLineHeight, lineCap: .round, dash: Metrics.unheardDash)
        context.stroke(line, with: .color(Palette.heard), style: style)
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
