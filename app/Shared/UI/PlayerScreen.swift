import SwiftUI

/// Full-screen playback. Only the video shows until the viewer asks for the controls.
///
/// Remote: select shows the controls, play/pause pauses, left and right skip 10 s while the
/// controls are hidden, Menu backs out of an open panel, hides the controls and then leaves. On the
/// focused progress bar, left and right jump (further with each quick tap) or, held, rewind and
/// fast forward until select, play/pause or Menu. macOS: space, arrows and Esc. While the controls
/// are hidden, the next episode's card takes focus near the end, ahead of a skip button.
struct PlayerScreen: View {
    @Environment(AppContext.self) private var app
    @State private var controlsVisible = true
    /// Bumped on every interaction; the controls hide 5 s after the last one.
    @State private var interactions = 0
    @FocusState private var focus: PlayerFocus?
    @State private var panel: PlayerPanel?
    /// The next episode's streams, open over the player when its card had no stream ready.
    @State private var nextStreams: StreamsRequest?

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
            }
            switch state {
            case .failed(_, let error):
                PlaybackFailure(error: error) { player.send(.stop) }
            case .active(let session) where session.phase == .opening || session.isBuffering:
                ProgressView().controlSize(.large)
            case .idle, .active:
                EmptyView()
            }
            if !controlsVisible {
                RemoteSurface(focus: $focus, interacted: poke)
            }
            if let session = state.session {
                if controlsVisible {
                    PlayerControls(
                        session: session, state: state, focus: $focus, panel: $panel, interacted: poke
                    )
                        .transition(.opacity)
                } else if let next = session.upNextCard {
                    UpNextCard(next: next, focus: $focus, play: { playNext(next) }, dismiss: { player.send(.upNext(.dismiss)) })
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(Metrics.screenPadding)
                } else if let segment = state.activeSegment {
                    SkipButton(segment: segment) { player.send(.skip(segment)) }
                        .focused($focus, equals: .skip)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(Metrics.screenPadding)
                }
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(state.statusLine)
        .accessibilityIdentifier("player.status")
        .onChange(of: controlsVisible, initial: true) { _, visible in
            focus = visible ? .playPause : restingFocus
        }
        .onChange(of: state.activeSegment) {
            guard !controlsVisible else { return }
            focus = restingFocus
        }
        .onChange(of: state.session?.upNextCard != nil) {
            guard !controlsVisible else { return }
            focus = restingFocus
        }
        .onChange(of: state.candidate) { nextStreams = nil }
        .sheet(isPresented: Binding { nextStreams != nil } set: { if !$0 { nextStreams = nil } }) {
            if let nextStreams {
                StreamsScreen(request: nextStreams)
                    #if os(macOS)
                    .presentationSizing(.page)
                    #endif
            }
        }
        .onChange(of: focus) { _, focused in
            // Moving between controls counts as using them.
            if focused != nil, focused != .surface { interactions += 1 }
        }
        .task(id: Autohide(interactions: interactions, isPlaying: isPlaying)) {
            guard (try? await Task.sleep(for: .seconds(5))) != nil else { return }
            // An open panel keeps the controls up.
            guard isPlaying, panel == nil else { return }
            controlsVisible = false
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
            if state.session?.scan != nil {
                player.send(.togglePause)
            } else if panel != nil {
                closePanel()
            } else if controlsVisible, state.session != nil {
                controlsVisible = false
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
            focus = .link(open)
            panel = parent
        } else {
            focus = open.button
            panel = nil
        }
    }

    private func poke() {
        controlsVisible = true
        interactions += 1
    }
}

/// The bare video while the controls are hidden: left and right skip one seek step, anything else shows the controls.
private struct RemoteSurface: View {
    @Environment(AppContext.self) private var app
    var focus: FocusState<PlayerFocus?>.Binding
    let interacted: () -> Void

    var body: some View {
        Color.clear
            .contentShape(.rect)
            .focusable()
            .focused(focus, equals: .surface)
            .onTapGesture(perform: interacted)
            .onMoveCommand { direction in
                switch direction {
                case .left: app.player.send(.jump(.backward))
                case .right: app.player.send(.jump(.forward))
                case .up, .down: interacted()
                @unknown default: break
                }
            }
    }
}

/// What holds focus: the bare video (remote commands), a control, the skip offer or the up next card.
enum PlayerFocus: Hashable {
    case surface
    case progress
    case back, playPause, forward
    case subtitles, audio, speed
    /// A choice on the open panel page, by position.
    case option(Int)
    /// A row on the open panel page that opens `PlayerPanel`.
    case link(PlayerPanel)
    case skip
    case playNext, dismissNext
}

/// Restarts the autohide countdown on every interaction and when playback starts or pauses.
private struct Autohide: Hashable {
    let interactions: Int
    let isPlaying: Bool
}

private struct PlaybackFailure: View {
    let error: PlaybackError
    let close: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Can't Play This Stream", systemImage: "exclamationmark.triangle")
        } description: {
            switch error {
            case .unsupported(let kind): Text("\(kind) streams can't be played here. Choose another stream.")
            case .failed(let reason): Text(reason)
            }
        } actions: {
            Button("Choose Another Stream", action: close)
        }
    }
}

/// "Skip Intro", "Skip Recap", "Skip Credits" or "Skip Preview".
private struct SkipButton: View {
    let segment: SkipSegment
    let skip: () -> Void

    var body: some View {
        Button(action: skip) {
            Label(segment.kind.skipTitle, systemImage: "forward.end.fill")
        }
        .accessibilityIdentifier("player.skip")
    }
}

/// The next episode's still and name, with buttons to play it now or turn it down.
private struct UpNextCard: View {
    let next: UpNext
    var focus: FocusState<PlayerFocus?>.Binding
    let play: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Artwork(url: next.thumbnail, title: next.title)
                .frame(width: Metrics.wideCardWidth, height: Metrics.wideCardWidth * 9 / 16)
                .clipShape(.rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Up Next").font(.caption).foregroundStyle(Palette.secondary)
                Text(episodeName).font(.headline).lineLimit(2)
            }
            .frame(width: Metrics.wideCardWidth, alignment: .leading)
            HStack {
                Button(action: play) {
                    Label(next.stream == nil ? "Choose Stream" : "Play Now", systemImage: "play.fill")
                }
                .focused(focus, equals: .playNext)
                .accessibilityIdentifier("player.upNext.play")
                Button("Cancel", action: dismiss)
                    .focused(focus, equals: .dismissNext)
                    .accessibilityIdentifier("player.upNext.dismiss")
            }
        }
        .padding(Metrics.playerPanelPadding)
        .background(Palette.canvas.opacity(0.85), in: .rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
        #if os(tvOS)
        .focusSection()
        #endif
    }

    /// "S1 E4 · The Big Day", or the episode number alone when it has no title.
    private var episodeName: String {
        guard case .episode(_, let season, let episode) = next.video else { return next.title }
        let number = "S\(season) E\(episode)"
        return next.title.isEmpty ? number : "\(number) · \(next.title)"
    }
}

extension SegmentKind {
    var skipTitle: String {
        switch self {
        case .recap: "Skip Recap"
        case .intro: "Skip Intro"
        case .outro: "Skip Credits"
        case .preview: "Skip Preview"
        }
    }
}
