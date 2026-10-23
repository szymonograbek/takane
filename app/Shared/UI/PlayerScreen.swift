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
/// the bare video, as does the stream ending or failing or the subtitles going off. Down from the
/// transport bar reaches the content tabs (Info, Episodes, Chapters) while the video plays on; up or
/// Menu goes back to the transport bar, and the controls stay up while focus is in the tabs.
struct PlayerScreen: View {
    @Environment(AppContext.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controls = Controls.hidden
    /// Bumped on every interaction; the controls hide a while after the last one.
    @State private var interactions = 0
    @FocusState private var focus: PlayerFocus?
    @State private var panel: PlayerPanel?
    /// An episode's streams, open over the player.
    @State private var nextStreams: StreamsRequest?
    /// How tall the controls or the subtitle timing strip are, which the subtitles rise above.
    @State private var coveredHeight: CGFloat = 0

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
                .offset(y: controls == .hidden ? 0 : -coveredHeight)
                // A tab covers the lower half of the picture, and the subtitles risen above it would leave the screen.
                .opacity(controls.openTab == nil ? 1 : 0)
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
                    openTiming: openTiming,
                    tabs: PlayerTabs(
                        session: session, open: controls.openTab, focus: $focus, openTab: { controls = .tabs($0) },
                        playEpisode: play, playChapter: play
                    )
                )
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { coveredHeight = $0 }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity)
            }
            if let session = state.session, controls == .timing {
                SubtitleTimingStrip(session: session, focus: $focus)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { coveredHeight = $0 }
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
            case (.peeking, .shown), (.shown, .shown), (.tabs, .shown), (_, .tabs): break
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
            if controls == .timing || controls.openTab != nil { controls = .hidden }
        }
        .onChange(of: canTimeSubtitles) {
            if !canTimeSubtitles, controls == .timing { controls = .hidden }
        }
        .sheet(isPresented: Binding { nextStreams != nil } set: { if !$0 { nextStreams = nil } }) {
            if let nextStreams {
                StreamsScreen(request: nextStreams)
                    #if os(macOS)
                    .presentationSizing(.page)
                    #endif
            }
        }
        .onChange(of: focus) { old, focused in
            // Moving between controls counts as using them, and leaving the progress bar keeps them up.
            guard let focused, focused != .surface else { return }
            interactions += 1
            if case .tab(let tab) = focused {
                let landing = tabLanding(reaching: tab, from: old)
                controls = .tabs(landing)
                if landing != tab { focus = .tab(landing) }
            } else if controls.openTab != nil, focused.isOnTransportBar {
                controls = .shown
            } else if controls == .peeking, focused != .progress {
                controls = .shown
            }
        }
        .task(id: Autohide(interactions: interactions, isPlaying: isPlaying, controls: controls)) {
            guard let delay = controls.autohideDelay, (try? await Task.sleep(for: delay)) != nil else { return }
            // An open panel keeps the controls up.
            guard isPlaying, panel == nil else { return }
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
            } else if controls.openTab != nil {
                backToTransportBar()
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

    /// Whether the subtitle timing strip has subtitles to move: they are on, and the stream has
    /// neither ended nor failed.
    private var canTimeSubtitles: Bool {
        app.player.state.session.map { $0.phase != .ended && $0.subtitleChoice != .off } ?? false
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

    /// Plays another episode of the season the way Up Next does: the offered one through its offer,
    /// any other by its streams over the player. The one playing goes back to the transport bar.
    private func play(_ episode: Video) {
        guard let session = app.player.state.session, episode.playable != session.candidate.item else {
            backToTransportBar()
            return
        }
        if case .offered(let next) = session.upNext, next.video == episode.playable {
            playNext(next)
        } else {
            nextStreams = StreamsRequest(
                video: episode.playable, title: session.meta?.name ?? session.title, backdrop: session.meta?.backdrop
            )
        }
    }

    /// Plays from the chapter's start, back on the progress bar so the viewer sees where it landed.
    private func play(_ chapter: Chapter) {
        app.player.send(.timeline(.chapter(chapter.id)))
        controls = .shown
        focus = .progress
    }

    /// Which tab opens when focus reaches `tab`'s name: the first coming down from the transport bar,
    /// the open one coming up from its content, else `tab` itself.
    private func tabLanding(reaching tab: PlayerFeature.Tab, from old: PlayerFocus?) -> PlayerFeature.Tab {
        switch old {
        case .episode, .chapter: controls.openTab ?? tab
        case let old? where old.isOnTransportBar: app.player.state.session?.tabs.first ?? tab
        case .some, nil: tab
        }
    }

    private func backToTransportBar() {
        controls = .shown
        focus = .playPause
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
private enum Controls: Hashable {
    case hidden
    /// Shown by a seek from the bare video, with focus on the progress bar, until the seeking stops.
    case peeking
    case shown
    /// Shown with a content tab open below them, while focus is in the tabs.
    case tabs(PlayerFeature.Tab)
    /// Hidden for the subtitle timing strip, until Menu.
    case timing

    var isVisible: Bool {
        switch self {
        case .peeking, .shown, .tabs: true
        case .hidden, .timing: false
        }
    }

    var openTab: PlayerFeature.Tab? {
        if case .tabs(let tab) = self { tab } else { nil }
    }

    /// How long the controls stay up after the last interaction, nil while they are not hiding by themselves.
    var autohideDelay: Duration? {
        switch self {
        case .peeking: .seconds(2)
        case .shown: .seconds(5)
        case .hidden, .tabs, .timing: nil
        }
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
    /// A tab's name below the transport bar.
    case tab(PlayerFeature.Tab)
    /// A card in the Episodes or Chapters tab.
    case episode(PlayableID)
    case chapter(Chapter.ID)

    /// The progress bar or a button of the transport bar.
    var isOnTransportBar: Bool {
        switch self {
        case .progress, .back, .playPause, .forward, .subtitles, .audio, .speed: true
        case .surface, .timing, .option, .link, .skip, .playNext, .dismissNext, .tab, .episode, .chapter: false
        }
    }
}

/// Restarts the autohide countdown on every interaction, when playback starts or pauses and when the controls change.
private struct Autohide: Hashable {
    let interactions: Int
    let isPlaying: Bool
    let controls: Controls
}
