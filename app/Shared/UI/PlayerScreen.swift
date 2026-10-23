import SwiftUI

/// Full-screen playback. Only the video shows until the viewer asks for the controls.
///
/// Remote: while the controls are hidden, pressing the clickpad's left or right edge skips one seek
/// step and shows the controls for a moment with the progress bar focused, and pressing its centre,
/// top or bottom shows them; swipes and a resting thumb do nothing. Play/pause pauses. Menu backs
/// out of an open panel, hides the controls and then leaves. On the focused progress bar, left and
/// right jump one step or, held, rewind and fast forward until select, play/pause or Menu. Quick
/// jumps in one direction add up beside the picture ("+30s"). macOS: space, arrows and Esc. While
/// the controls are hidden, the next episode's card takes focus near the end, ahead of a skip button.
/// Subtitles › Timing swaps the controls for the subtitle timing strip, and Menu swaps it back for
/// the bare video.
struct PlayerScreen: View {
    @Environment(AppContext.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controls = Controls.hidden
    /// Bumped on every interaction; the controls hide a while after the last one.
    @State private var interactions = 0
    @FocusState private var focus: PlayerFocus?
    @State private var panel: PlayerPanel?
    /// The next episode's streams, open over the player when its card had no stream ready.
    @State private var nextStreams: StreamsRequest?
    /// How tall the subtitle timing strip is, which the subtitles rise above.
    @State private var timingHeight: CGFloat = 0

    var body: some View {
        let player = app.player
        let state = player.state
        ZStack {
            Color.black
            app.services.videoSurface()
            if let session = state.session {
                SubtitleOverlay(
                    cues: session.subtitles, videoSize: session.videoSize,
                    style: app.preferences.state.preferences?.subtitleStyle ?? .defaults
                )
                .offset(y: controls == .timing ? -timingHeight : 0)
            }
            switch state {
            case .failed(_, let error):
                PlaybackFailure(error: error) { player.send(.stop) }
            case .active(let session) where session.phase == .opening || session.isBuffering:
                LoadingSpinner()
            case .idle, .active:
                EmptyView()
            }
            if let session = state.session {
                StreakBadge(streak: session.streak)
            }
            if controls == .hidden {
                // A live channel does not seek, so its arrows only show the controls.
                RemoteSurface(focus: $focus, interacted: poke, stepped: state.session?.isLive == true ? poke : peek)
            }
            if let session = state.session, controls.isVisible {
                PlayerControls(
                    session: session, state: state, focus: $focus, panel: $panel, interacted: poke,
                    openTiming: openTiming
                )
                    .transition(.opacity)
            }
            if let session = state.session, controls == .timing {
                SubtitleTimingStrip(session: session, focus: $focus)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { timingHeight = $0 }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            // A layer of its own, so a change of what rests over the video animates only this.
            ZStack {
                if let session = state.session, controls == .hidden {
                    if let next = session.upNextCard {
                        UpNextCard(next: next, focus: $focus, play: { playNext(next) }, dismiss: { player.send(.upNext(.dismiss)) })
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(Metrics.screenPadding)
                            .transition(restingTransition)
                    } else if let segment = state.activeSegment {
                        SkipButton(segment: segment) { player.send(.skip(segment)) }
                            .focused($focus, equals: .skip)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(Metrics.screenPadding)
                            .transition(restingTransition)
                    }
                }
            }
            .animation(Motion.appear, value: restingFocus)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: controls)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(state.statusLine)
        .accessibilityIdentifier("player.status")
        .onChange(of: controls, initial: true) { old, new in
            switch (old, new) {
            case (_, .hidden): focus = restingFocus
            case (_, .peeking): focus = .progress
            // Stays where the viewer moved it from the progress bar.
            case (.peeking, .shown), (.shown, .shown): break
            case (.hidden, .shown), (.timing, .shown): focus = .playPause
            case (_, .timing): focus = .timing
            }
        }
        .onChange(of: state.activeSegment) {
            guard controls == .hidden else { return }
            focus = restingFocus
        }
        .onChange(of: state.session?.upNextCard != nil) {
            guard controls == .hidden else { return }
            focus = restingFocus
        }
        .onChange(of: state.candidate) {
            nextStreams = nil
            if controls == .timing { controls = .hidden }
        }
        .sheet(isPresented: Binding { nextStreams != nil } set: { if !$0 { nextStreams = nil } }) {
            if let nextStreams {
                StreamsScreen(request: nextStreams)
                    #if os(macOS)
                    .presentationSizing(.page)
                    #endif
            }
        }
        .onChange(of: focus) { _, focused in
            // Moving between controls counts as using them, and leaving the progress bar keeps them up.
            guard let focused, focused != .surface else { return }
            interactions += 1
            if controls == .peeking, focused != .progress { controls = .shown }
        }
        .task(id: Autohide(interactions: interactions, isPlaying: isPlaying, controls: controls)) {
            guard (try? await Task.sleep(for: controls.autohideDelay)) != nil else { return }
            // An open panel keeps the controls up.
            guard isPlaying, panel == nil, controls.isVisible else { return }
            controls = .hidden
        }
        #if os(tvOS)
        .onPlayPauseCommand {
            player.send(.togglePause)
            poke()
        }
        #else
        .onContinuousHover { _ in poke() }
        .onKeyPress(.space) {
            player.send(.togglePause)
            poke()
            return .handled
        }
        #endif
        .onExitCommand {
            if controls == .timing {
                controls = .hidden
            } else if state.session?.scan != nil {
                player.send(.togglePause)
            } else if panel != nil {
                closePanel()
            } else if controls.isVisible, state.session != nil {
                controls = .hidden
            } else {
                player.send(.stop)
            }
        }
    }

    /// Playing at normal speed, so the controls may hide. A scan keeps them up.
    private var isPlaying: Bool {
        app.player.state.session.map { $0.phase == .playing && $0.scan == nil } ?? false
    }

    /// Where focus rests while the controls are hidden: the up next card, the skip button or the bare video.
    private var restingFocus: PlayerFocus {
        if app.player.state.session?.upNextCard != nil {
            .playNext
        } else if app.player.state.activeSegment != nil {
            .skip
        } else {
            .surface
        }
    }

    /// The up next card and the skip button grow from the corner they rest in.
    private var restingTransition: AnyTransition {
        Motion.surface(from: .bottomTrailing, reduceMotion: reduceMotion)
    }

    /// Plays the next episode, or opens its streams over the player when no stream for it is ready.
    private func playNext(_ next: UpNext) {
        app.player.send(.upNext(.play))
        if next.stream == nil {
            nextStreams = StreamsRequest(video: next.video, title: next.show, backdrop: next.backdrop)
        }
    }

    /// Goes back to the page that opened this one, or closes the panel onto its button.
    private func closePanel() {
        guard let open = panel else { return }
        if let parent = open.parent {
            panel = parent
            // Once the parent's rows are in place; until then the focus engine moves focus off the
            // closed page's row to the parent's first.
            Task { focus = .link(open) }
        } else {
            focus = open.button
            panel = nil
        }
    }

    private func openTiming() {
        panel = nil
        controls = .timing
    }

    private func poke() {
        if controls == .hidden { controls = .shown }
        interactions += 1
    }

    /// A seek from the bare video shows the controls only for a moment.
    private func peek() {
        if controls == .hidden { controls = .peeking }
        interactions += 1
    }
}

/// Whether the transport bar shows, and why.
private enum Controls: Equatable {
    case hidden
    /// Shown by a seek from the bare video, with focus on the progress bar, until the seeking stops.
    case peeking
    case shown
    /// Hidden for the subtitle timing strip, until Menu.
    case timing

    var isVisible: Bool { self == .peeking || self == .shown }

    var autohideDelay: Duration {
        self == .peeking ? .seconds(2) : .seconds(5)
    }
}

/// How far a streak of quick jumps has gone, beside the picture on the side it jumps to ("+30s"),
/// for a moment after each tap.
private struct StreakBadge: View {
    let streak: PlayerFeature.StepStreak?
    @State private var shown: PlayerFeature.StepStreak?

    var body: some View {
        // A view that is always there, so the task runs before the first streak.
        Color.clear
            .overlay(alignment: shown?.direction == .forward ? .trailing : .leading) {
                if let shown {
                    VStack(spacing: 8) {
                        Image(systemName: shown.direction == .forward ? "goforward" : "gobackward")
                            .font(.largeTitle)
                        Text(distance(shown)).font(.title3).bold().monospacedDigit()
                    }
                    .foregroundStyle(Palette.text)
                    .shadow(color: .black.opacity(0.6), radius: 8)
                    .padding(.horizontal, Metrics.screenPadding)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: shown == nil)
            .task(id: streak) {
                shown = streak
                guard streak != nil, (try? await Task.sleep(for: PlayerFeature.streakWindow)) != nil else { return }
                shown = nil
            }
    }

    /// "+30s", "−1m 30s".
    private func distance(_ streak: PlayerFeature.StepStreak) -> String {
        let sign = streak.direction == .forward ? "+" : "−"
        return sign + streak.distance.formatted(.units(allowed: [.minutes, .seconds], width: .narrow))
    }
}

/// The bare video while the controls are hidden: left and right skip one seek step, anything else shows the controls.
private struct RemoteSurface: View {
    @Environment(AppContext.self) private var app
    var focus: FocusState<PlayerFocus?>.Binding
    let interacted: () -> Void
    /// After a skip.
    let stepped: () -> Void

    var body: some View {
        #if os(tvOS)
        // Presses only: a swipe from a resting thumb arrives as a move command and would seek.
        RemotePresses(
            arrow: { isDown, direction in
                if isDown { step(direction) }
            },
            vertical: interacted,
            select: interacted
        )
        .focused(focus, equals: .surface)
        #else
        Color.clear
            .contentShape(.rect)
            .focusable()
            .focused(focus, equals: .surface)
            .onTapGesture(perform: interacted)
            .onMoveCommand { direction in
                switch direction {
                case .left: step(.backward)
                case .right: step(.forward)
                case .up, .down: interacted()
                @unknown default: break
                }
            }
        #endif
    }

    private func step(_ direction: PlayerFeature.Direction) {
        app.player.send(.timeline(.step(direction, at: .now)))
        stepped()
    }
}

/// What holds focus: the bare video (remote commands), a control, the skip offer or the up next card.
enum PlayerFocus: Hashable {
    case surface
    case progress
    case back, playPause, forward
    case subtitles, audio, speed
    /// The subtitle timing strip.
    case timing
    /// A choice on the open panel page, by position.
    case option(Int)
    /// A row on the open panel page that opens `PlayerPanel`.
    case link(PlayerPanel)
    case skip
    case playNext, dismissNext
}

/// Restarts the autohide countdown on every interaction, when playback starts or pauses and when the controls change.
private struct Autohide: Hashable {
    let interactions: Int
    let isPlaying: Bool
    let controls: Controls
}

private struct PlaybackFailure: View {
    let error: PlaybackError
    let close: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Can't Play This Stream", systemImage: "exclamationmark.triangle")
        } description: {
            switch error {
            case .unsupported: Text("Takane can't play this kind of stream. Choose another stream.")
            case .failed(let reason): Text(reason)
            }
        } actions: {
            Button("Choose Another Stream", action: close)
        }
    }
}

/// The spinner for opening or buffering, held back for the first 2 s so a short wait shows only black.
/// Each wait gets a fresh view, so the delay restarts with it.
private struct LoadingSpinner: View {
    @State private var isShown = false

    var body: some View {
        ProgressView()
            .controlSize(.large)
            .opacity(isShown ? 1 : 0)
            .task {
                guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
                isShown = true
            }
    }
}
