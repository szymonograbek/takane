import SwiftUI

/// The transport bar: title, progress, and buttons for skipping, pausing and choosing tracks and speed.
struct PlayerControls: View {
    @Environment(AppContext.self) private var app
    let session: PlayerFeature.Session
    let state: PlayerFeature.State
    var focus: FocusState<PlayerFocus?>.Binding
    let interacted: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text(session.title.isEmpty ? session.candidate.name ?? "" : session.title)
                .font(.title3).bold()
            TimelineBar(session: session, focus: focus, interacted: interacted)
            HStack {
                Text(session.displayedPosition.clock)
                Spacer()
                if let scan = session.scan {
                    Label("\(scan.rate.rawValue)×", systemImage: scan.direction == .forward ? "forward.fill" : "backward.fill")
                        .foregroundStyle(Palette.text)
                }
                Spacer()
                Text("−" + (session.duration - session.displayedPosition).clock)
            }
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            HStack(spacing: 20) {
                transportButtons
                Spacer()
                SubtitleMenu(session: session, interacted: interacted)
                    .focused(focus, equals: .subtitles)
                AudioMenu(tracks: state.tracks(.audio), interacted: interacted)
                    .focused(focus, equals: .audio)
                SpeedMenu(speed: session.speed, interacted: interacted)
                    .focused(focus, equals: .speed)
            }
            #if os(tvOS)
            .focusSection()
            #endif
        }
        .padding(Metrics.screenPadding)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .frame(height: 520)
        }
    }

    private var transportButtons: some View {
        HStack(spacing: 20) {
            control("Back 10 Seconds", systemImage: "gobackward.10") { app.player.send(.seek(by: .seconds(-10))) }
                .focused(focus, equals: .back)
            control(session.phase == .paused ? "Play" : "Pause", systemImage: session.phase == .paused ? "play.fill" : "pause.fill") {
                app.player.send(.togglePause)
            }
            .focused(focus, equals: .playPause)
            .accessibilityIdentifier("player.playPause")
            control("Forward 10 Seconds", systemImage: "goforward.10") { app.player.send(.seek(by: .seconds(10))) }
                .focused(focus, equals: .forward)
        }
    }

    private func control(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            interacted()
        } label: {
            Label(title, systemImage: systemImage).labelStyle(.iconOnly)
        }
    }
}

/// The progress line, focusable: left and right tap to jump or hold to scan, select plays or pauses.
private struct TimelineBar: View {
    /// A left or right press still down, until it has lasted long enough to count as a hold.
    private enum Press {
        case pending(PlayerFeature.Direction, Task<Void, Never>)
        case held
    }

    private static let holdThreshold = Duration.milliseconds(500)

    @Environment(AppContext.self) private var app
    let session: PlayerFeature.Session
    var focus: FocusState<PlayerFocus?>.Binding
    let interacted: () -> Void
    @State private var press: Press?

    var body: some View {
        let focused = focus.wrappedValue == .progress
        ProgressLine(
            fraction: session.duration > .zero ? session.displayedPosition / session.duration : 0,
            height: focused ? Metrics.focusedProgressHeight : Metrics.progressHeight
        )
        .frame(height: Metrics.focusedProgressHeight)
        .animation(.easeOut(duration: 0.15), value: focused)
        #if os(tvOS)
        .overlay {
            RemotePresses(arrow: pressed, select: togglePause)
                .focused(focus, equals: .progress)
        }
        .focusSection()
        #else
        .contentShape(.rect)
        .focusable()
        .focused(focus, equals: .progress)
        .onTapGesture(perform: togglePause)
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .up]) { key in
            pressed(key.phase == .down, key.key == .leftArrow ? .backward : .forward)
            return .handled
        }
        #endif
        .accessibilityIdentifier("player.progress")
    }

    private func togglePause() {
        app.player.send(.togglePause)
        interacted()
    }

    private func pressed(_ isDown: Bool, _ direction: PlayerFeature.Direction) {
        if isDown { began(direction) } else { ended() }
        interacted()
    }

    private func began(_ direction: PlayerFeature.Direction) {
        guard press == nil else { return }
        press = .pending(direction, Task {
            guard (try? await Task.sleep(for: Self.holdThreshold)) != nil else { return }
            press = .held
            app.player.send(.timeline(.hold(direction)))
        })
    }

    private func ended() {
        if case .pending(let direction, let task) = press {
            task.cancel()
            app.player.send(.timeline(.step(direction, at: .now)))
        }
        press = nil
    }
}

#if os(tvOS)
/// A focusable UIKit view that reports the remote's arrows going down and up. SwiftUI on tvOS
/// sees the Siri Remote's arrows only as move commands, with no release to tell a tap from a hold.
private struct RemotePresses: UIViewRepresentable {
    let arrow: (Bool, PlayerFeature.Direction) -> Void
    let select: () -> Void

    func makeUIView(context: Context) -> PressView { PressView() }

    func updateUIView(_ view: PressView, context: Context) {
        view.arrow = arrow
        view.select = select
    }

    final class PressView: UIView {
        var arrow: (Bool, PlayerFeature.Direction) -> Void = { _, _ in }
        var select: () -> Void = {}

        override var canBecomeFocused: Bool { true }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            super.pressesBegan(presses.filter { !handle($0, isDown: true) }, with: event)
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            super.pressesEnded(presses.filter { !handle($0, isDown: false) }, with: event)
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            super.pressesCancelled(presses.filter { !handle($0, isDown: false) }, with: event)
        }

        private func handle(_ press: UIPress, isDown: Bool) -> Bool {
            switch press.type {
            case .leftArrow: arrow(isDown, .backward)
            case .rightArrow: arrow(isDown, .forward)
            case .select: if !isDown { select() }
            default: return false
            }
            return true
        }
    }
}
#endif

/// The stream's own tracks first, then a submenu per add-on with its files grouped by language.
private struct SubtitleMenu: View {
    @Environment(AppContext.self) private var app
    let session: PlayerFeature.Session
    let interacted: () -> Void

    var body: some View {
        let selection = Binding(get: { session.subtitleChoice }, set: choose)
        Menu {
            Section("Built-in") {
                Picker("Built-in", selection: selection) {
                    Text("Off").tag(PlayerFeature.SubtitleChoice.off)
                    ForEach(session.builtInSubtitles) { Text($0.label).tag(PlayerFeature.SubtitleChoice.builtIn($0.id)) }
                }
                .pickerStyle(.inline)
            }
            if !session.addonSubtitles.isEmpty {
                Section("Add-ons") {
                    ForEach(session.addonSubtitles) { source in
                        AddonSubtitleMenu(
                            source: source,
                            preferred: app.preferences.state.playback?.languages.subtitles,
                            selection: selection
                        )
                    }
                }
            }
        } label: {
            Label("Subtitles", systemImage: "captions.bubble").labelStyle(.iconOnly)
        }
        .accessibilityIdentifier("player.subtitles")
    }

    private func choose(_ choice: PlayerFeature.SubtitleChoice) {
        app.player.send(.chooseSubtitles(choice))
        interacted()
    }
}

/// One add-on's files, a section per language with the preferred language first.
private struct AddonSubtitleMenu: View {
    private struct LanguageGroup: Identifiable {
        let language: String
        var files: [AddonSubtitle]

        var id: String { language }
    }

    let source: SubtitleSource
    let preferred: Language?
    let selection: Binding<PlayerFeature.SubtitleChoice>

    var body: some View {
        Menu(source.addonName) {
            switch source.subtitles {
            case .loading:
                Text("Loading…")
            case .failed:
                Text("Unavailable")
            case .loaded(let files) where files.isEmpty:
                Text("None Found")
            case .loaded(let files):
                ForEach(groups(files)) { group in
                    let name = languageName(group.language)
                    Section(name) {
                        Picker(name, selection: selection) {
                            ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                                Text(file.label ?? "\(name) \(index + 1)").tag(PlayerFeature.SubtitleChoice.addon(file.id))
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }
            }
        }
        .accessibilityIdentifier("player.subtitles.addon")
    }

    private func groups(_ files: [AddonSubtitle]) -> [LanguageGroup] {
        var groups: [LanguageGroup] = []
        for file in files {
            if let index = groups.firstIndex(where: { $0.language == file.language }) {
                groups[index].files.append(file)
            } else {
                groups.append(LanguageGroup(language: file.language, files: [file]))
            }
        }
        if let preferred, let index = groups.firstIndex(where: { Language($0.language) == preferred }) {
            groups.insert(groups.remove(at: index), at: 0)
        }
        return groups
    }
}

private struct AudioMenu: View {
    @Environment(AppContext.self) private var app
    let tracks: [MediaTrack]
    let interacted: () -> Void

    var body: some View {
        Menu {
            Picker("Audio", selection: Binding(get: { tracks.first(where: \.isSelected)?.id }, set: choose)) {
                ForEach(tracks) { Text($0.label).tag(Optional($0.id)) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Audio", systemImage: "speaker.wave.2").labelStyle(.iconOnly)
        }
        .disabled(tracks.count < 2)
        .accessibilityIdentifier("player.audio")
    }

    private func choose(_ track: MediaTrack.ID?) {
        if let track { app.player.send(.select(track)) }
        interacted()
    }
}

private struct SpeedMenu: View {
    @Environment(AppContext.self) private var app
    let speed: PlaybackSpeed
    let interacted: () -> Void

    var body: some View {
        Menu {
            Picker("Speed", selection: Binding(get: { speed }, set: choose)) {
                ForEach(PlaybackSpeed.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Speed", systemImage: "gauge.with.dots.needle.50percent").labelStyle(.iconOnly)
        }
        .accessibilityIdentifier("player.speed")
    }

    private func choose(_ speed: PlaybackSpeed) {
        app.player.send(.setSpeed(speed))
        interacted()
    }
}

extension MediaTrack {
    /// "English · 5.1 · eac3", "Polish (Forced)", or the track number when the stream says nothing.
    var label: String {
        let language = language.map(languageName)
        var name = [title, language].compactMap(\.self).first ?? "Track \(id.number)"
        if let language, let title, !title.localizedCaseInsensitiveContains(language) { name = "\(language) · \(title)" }
        if isForced { name += " (Forced)" }
        var parts = [name]
        if let channelCount { parts.append(Self.channelLayout(channelCount)) }
        if id.kind == .audio, let codec { parts.append(codec) }
        return parts.joined(separator: " · ")
    }

    private static func channelLayout(_ count: Int) -> String {
        switch count {
        case 1: "Mono"
        case 2: "Stereo"
        case 6: "5.1"
        case 8: "7.1"
        default: "\(count) ch"
        }
    }
}

/// "English" for `eng` or `en`, or the code itself when the system does not know it.
private func languageName(_ code: String) -> String {
    Locale.current.localizedString(forLanguageCode: code) ?? code
}

extension PlaybackSpeed {
    var label: String {
        rawValue == 1 ? "Normal" : "\(rawValue.formatted())×"
    }
}
