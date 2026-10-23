import SwiftUI

/// Sync mode: a strip along the bottom of the playing video for moving the subtitles earlier or
/// later. It reads the delay in words and shows the subtitles' cues sliding past a playhead fixed in
/// the middle, each with a dashed outline where its file times it.
///
/// Remote: left and right move the subtitles a fine step earlier or later as they go down, and
/// held, a coarse step at a time until released. Select starts the highlighted line, the one
/// nearest the playhead, now. Play/pause and Menu stay the player's, which leaves the strip on
/// Menu. Swipes do nothing. macOS: arrows, Return, space and Esc.
struct SubtitleTimingStrip: View {
    private static let holdThreshold = Duration.milliseconds(500)
    private static let repeatInterval = Duration.milliseconds(250)

    @Environment(AppContext.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textLayout) private var textLayout
    let session: PlayerFeature.Session
    var focus: FocusState<PlayerFocus?>.Binding
    /// The left or right press down, until it ends.
    @State private var press: PlayerFeature.Direction?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.shelfSpacing) {
                Text("Subtitle Timing").font(.title3).bold()
                Text(session.subtitleDelay.label)
                    .font(.title2).bold().monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(value: session.subtitleDelay.duration / .seconds(1)))
                    .animation(Motion.appear, value: session.subtitleDelay)
                    .accessibilityIdentifier("player.timing.offset")
            }
            CueLanes(session: session, target: session.alignmentTarget)
            hints
        }
        .foregroundStyle(Palette.text)
        .padding(Metrics.screenPadding)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, Palette.scrim], startPoint: .top, endPoint: .bottom)
                .frame(height: Metrics.scrimHeight)
        }
        .overlay { remote }
        .task(id: press) { await repeatWhileHeld() }
    }

    /// Takes the presses, over the whole strip.
    @ViewBuilder
    private var remote: some View {
        #if os(tvOS)
        RemotePresses(arrow: pressed, vertical: {}, select: align)
            .focused(focus, equals: .timing)
            .accessibilityLabel("Subtitle Timing")
            .accessibilityValue(session.subtitleDelay.label)
            .accessibilityAdjustableAction(adjust)
            .accessibilityIdentifier("player.timing")
        #else
        Color.clear
            .contentShape(.rect)
            .focusable()
            .focusEffectDisabled()
            .focused(focus, equals: .timing)
            .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .up]) { key in
                pressed(key.phase == .down, key.key == .leftArrow ? .backward : .forward)
                return .handled
            }
            .onKeyPress(.return) {
                align()
                return .handled
            }
            .accessibilityLabel("Subtitle Timing")
            .accessibilityValue(session.subtitleDelay.label)
            .accessibilityAdjustableAction(adjust)
            .accessibilityIdentifier("player.timing")
        #endif
    }

    private var hints: some View {
        let layout = textLayout == .large
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.timingLaneSpacing))
            : AnyLayout(HStackLayout(spacing: Metrics.sectionSpacing))
        return layout {
            #if os(tvOS)
            hint(Text("\(Image(systemName: "chevron.left")) \(Image(systemName: "chevron.right"))"), Self.stepHint)
            hint(Text("Click"), alignHint)
            hint(Text(Image(systemName: "playpause.fill")), "Play or pause")
            hint(Text("Menu"), "Done")
            #else
            hint(Text("\(Image(systemName: "arrow.left")) \(Image(systemName: "arrow.right"))"), Self.stepHint)
            hint(Text("Return"), alignHint)
            hint(Text("Space"), "Play or pause")
            hint(Text("Esc"), "Done")
            #endif
        }
        .font(.caption)
    }

    private static let stepHint = "0.1 s earlier or later · hold to move faster"

    private var alignHint: String {
        session.alignmentTarget == nil ? "No line nearby" : "This line starts now"
    }

    private func hint(_ key: Text, _ action: String) -> some View {
        HStack(spacing: Metrics.timingLaneSpacing) {
            key.bold()
            Text(action).foregroundStyle(Palette.secondary)
        }
    }

    /// A press moves the subtitles a fine step as it goes down, so it shows at once whether held or not.
    private func pressed(_ isDown: Bool, _ direction: PlayerFeature.Direction) {
        if isDown, press == nil {
            nudge(direction, .fine)
            press = direction
        } else if !isDown, press == direction {
            press = nil
        }
    }

    /// A press held past `holdThreshold` moves the subtitles a coarse step then and every
    /// `repeatInterval` after, until it ends.
    private func repeatWhileHeld() async {
        guard let press, (try? await Task.sleep(for: Self.holdThreshold)) != nil else { return }
        repeat {
            nudge(press, .coarse)
        } while (try? await Task.sleep(for: Self.repeatInterval)) != nil
    }

    private func nudge(_ direction: PlayerFeature.Direction, _ step: SubtitleDelay.Step) {
        app.player.send(.subtitleTiming(.nudge(direction, step)))
    }

    private func align() {
        app.player.send(.subtitleTiming(.align))
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment: nudge(.forward, .fine)
        case .decrement: nudge(.backward, .fine)
        @unknown default: break
        }
    }
}

/// The strip's lanes, each named on the left. The subtitles lane shows the cues within
/// `PlayerFeature.alignmentWindow` of the playhead, which stays in the middle while they glide past,
/// with `target`, the line select starts, highlighted.
private struct CueLanes: View {
    /// A position the engine reported and when it arrived.
    private struct Report {
        let position: Duration
        let date: Date
    }

    /// The longest the cues glide on from a report before waiting for the next.
    private static let maxGlide = 0.5

    let session: PlayerFeature.Session
    let target: TimedCue?
    @State private var lastReport: Report?

    var body: some View {
        let cues = visibleCues
        HStack(spacing: Metrics.timingLaneSpacing) {
            VStack(alignment: .leading, spacing: Metrics.timingLaneSpacing) {
                Text("Subtitles")
                    .frame(height: Metrics.timingLaneHeight)
            }
            .font(.caption)
            .foregroundStyle(Palette.secondary)
            .frame(width: Metrics.timingLabelWidth, alignment: .leading)
            TimelineView(.animation(paused: !isMoving)) { context in
                VStack(spacing: Metrics.timingLaneSpacing) {
                    CueTrack(cues: cues, delay: session.subtitleDelay, target: target?.id, playhead: playhead(at: context.date))
                }
            }
            .overlay { Playhead() }
        }
        .padding(Metrics.timingLaneSpacing)
        .padding(.leading, Metrics.timingLaneSpacing)
        .background(Palette.lane, in: .rect(cornerRadius: Metrics.cornerRadius))
        .onChange(of: session.position, initial: true) {
            lastReport = Report(position: session.position, date: .now)
        }
        // Gliding starts and stops from where the engine is, not from the last report's time.
        .onChange(of: isMoving) {
            lastReport = Report(position: session.position, date: .now)
        }
        .accessibilityHidden(true)
    }

    private var isMoving: Bool {
        session.phase == .playing && !session.isBuffering
    }

    /// Where the playhead is at `date`: the engine reports a few times a second, so while playing it
    /// moves on from the last report at the playback speed.
    private func playhead(at date: Date) -> Duration {
        guard let lastReport else { return session.position }
        guard isMoving else { return lastReport.position }
        let elapsed = min(max(date.timeIntervalSince(lastReport.date), 0), Self.maxGlide)
        return lastReport.position + .seconds(elapsed * session.speed.rawValue)
    }

    /// The cues shown, or outlined where their file times them, near the playhead.
    private var visibleCues: [TimedCue] {
        let reach = PlayerFeature.alignmentWindow + .seconds(Self.maxGlide * 2)
        let window = (session.position - reach)...(session.position + reach)
        let delay = session.subtitleDelay.duration
        return session.cueTimeline.filter { cue in
            cue.range.overlaps(window) || (cue.range.lowerBound + delay ..< cue.range.upperBound + delay).overlaps(window)
        }
    }
}

/// One lane of cues, moved so `playhead` is in the middle. Each cue is a block where it shows and,
/// once the subtitles are moved, a dashed outline where its file times it. The `target` block is lit.
private struct CueTrack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cues: [TimedCue]
    let delay: SubtitleDelay
    let target: TimedCue.ID?
    let playhead: Duration

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / (2 * (PlayerFeature.alignmentWindow / .seconds(1)))
            ZStack(alignment: .leading) {
                if delay != .zero {
                    ForEach(cues) { cue in
                        CueOutline(width: width(of: cue, scale: scale))
                            .offset(x: (cue.range.lowerBound / .seconds(1)) * scale)
                    }
                }
                ZStack(alignment: .leading) {
                    ForEach(cues) { cue in
                        let shown = cue.range.lowerBound + delay.duration ..< cue.range.upperBound + delay.duration
                        CueBlock(cue: cue, width: width(of: cue, scale: scale), isTarget: cue.id == target)
                            .offset(x: (shown.lowerBound / .seconds(1)) * scale)
                    }
                }
                .animation(reduceMotion ? nil : Motion.appear, value: delay)
            }
            .offset(x: geometry.size.width / 2 - (playhead / .seconds(1)) * scale)
        }
        .frame(height: Metrics.timingLaneHeight)
        .clipped()
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: Metrics.timingLaneFade),
                    .init(color: .black, location: 1 - Metrics.timingLaneFade), .init(color: .clear, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }

    private func width(of cue: TimedCue, scale: CGFloat) -> CGFloat {
        max(((cue.range.upperBound - cue.range.lowerBound) / .seconds(1)) * scale, Metrics.cueMinWidth)
    }
}

/// A cue where it shows, with its first words. The line select starts gets a bright border.
private struct CueBlock: View {
    let cue: TimedCue
    let width: CGFloat
    let isTarget: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cornerRadius / 2, style: .continuous)
        shape.fill(Palette.burgundy)
            .overlay { shape.strokeBorder(isTarget ? Palette.text : Palette.cueEdge, lineWidth: Metrics.cueBorder) }
            .overlay(alignment: .leading) {
                if width >= Metrics.cueTextMinWidth {
                    Text(cue.text.rawValue)
                        .font(.caption2)
                        .lineLimit(1)
                        .padding(.horizontal, Metrics.timingLaneSpacing)
                }
            }
            .frame(width: width, height: Metrics.timingLaneHeight)
    }
}

/// Where a cue showed before the subtitles were moved.
private struct CueOutline: View {
    let width: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: Metrics.cornerRadius / 2, style: .continuous)
            .strokeBorder(Palette.secondary, style: StrokeStyle(lineWidth: Metrics.cueBorder, dash: Metrics.cueOutlineDash))
            .frame(width: width, height: Metrics.timingLaneHeight)
    }
}

/// Now: a glowing line across the lanes.
private struct Playhead: View {
    var body: some View {
        Rectangle()
            .fill(Palette.text)
            .frame(width: Metrics.playheadWidth)
            .shadow(color: Palette.playheadGlow, radius: Metrics.playheadGlowRadius)
            .padding(.vertical, -Metrics.timingLaneSpacing / 2)
    }
}

extension SubtitleDelay {
    /// "In Sync", "0.8 s Later", "0.3 s Earlier".
    var label: String {
        let tenths = (duration / .milliseconds(100)).rounded()
        guard tenths != 0 else { return "In Sync" }
        let seconds = (abs(tenths) / 10).formatted(.number.precision(.fractionLength(1)))
        return tenths > 0 ? "\(seconds) s Later" : "\(seconds) s Earlier"
    }
}
