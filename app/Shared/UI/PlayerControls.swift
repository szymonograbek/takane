import SwiftUI

/// The transport bar: title, progress, and buttons for skipping, pausing and choosing tracks and speed.
struct PlayerControls: View {
    @Environment(AppContext.self) private var app
    let session: PlayerFeature.Session
    let state: PlayerFeature.State
    var focus: FocusState<PlayerFocus?>.Binding
    @Binding var panel: PlayerPanel?
    let interacted: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text(session.title.isEmpty ? session.candidate.name ?? "" : session.title)
                .font(.title3).bold()
            TimelineBar(session: session, focus: focus, interacted: interacted)
                .disabled(panel != nil)
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
                panelButton(.subtitles)
                    .accessibilityIdentifier("player.subtitles")
                panelButton(.audio)
                    .disabled(state.tracks(.audio).isEmpty)
                    .accessibilityIdentifier("player.audio")
                panelButton(.speed)
                    .accessibilityIdentifier("player.speed")
            }
            // An open panel keeps focus among its rows until a choice is made or Menu closes it.
            .disabled(panel != nil)
            #if os(tvOS)
            .focusSection()
            #endif
            .overlay(alignment: .topTrailing) {
                if let panel {
                    // Rises from the row's top edge. Laid out there, not offset, so the focus engine
                    // sees the rows where they are drawn.
                    OptionsPanel(sections: sections(for: panel), focus: focus, choose: choose, open: open)
                        .padding(.bottom, 24)
                        .frame(height: 0, alignment: .bottom)
                }
            }
        }
        .padding(Metrics.screenPadding)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .frame(height: 520)
        }
    }

    private var transportButtons: some View {
        let seconds = session.seekStep.seconds
        return HStack(spacing: 20) {
            control("Back \(seconds) Seconds", systemImage: "gobackward.\(seconds)") { app.player.send(.jump(.backward)) }
                .focused(focus, equals: .back)
            control(session.phase == .paused ? "Play" : "Pause", systemImage: session.phase == .paused ? "play.fill" : "pause.fill") {
                app.player.send(.togglePause)
            }
            .focused(focus, equals: .playPause)
            .accessibilityIdentifier("player.playPause")
            control("Forward \(seconds) Seconds", systemImage: "goforward.\(seconds)") { app.player.send(.jump(.forward)) }
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

    private func panelButton(_ kind: PlayerPanel) -> some View {
        control(kind.title, systemImage: kind.systemImage) { open(kind) }
            .focused(focus, equals: kind.button)
    }

    /// Shows `page` with focus on its current choice, or on its first row that takes focus.
    private func open(_ page: PlayerPanel) {
        let targets = sections(for: page).flatMap(\.rows).enumerated().compactMap { index, row in
            row.focus(at: index).map { (focus: $0, isSelected: row.isSelected) }
        }
        panel = page
        focus.wrappedValue = (targets.first(where: \.isSelected) ?? targets.first)?.focus ?? page.button
        interacted()
    }

    private func choose(_ event: PlayerFeature.Event) {
        app.player.send(event)
        if let panel { focus.wrappedValue = panel.button }
        panel = nil
        interacted()
    }

    private func sections(for page: PlayerPanel) -> [PanelSection] {
        switch page {
        case .subtitles:
            let choice = session.subtitleChoice
            let builtIn = [PanelRow.choice("Off", isSelected: choice == .off, .chooseSubtitles(.off))]
                + session.builtInSubtitles.map { track in
                    .choice(track.label, isSelected: choice == .builtIn(track.id), .chooseSubtitles(.builtIn(track.id)))
                }
            guard !session.addonSubtitles.isEmpty else { return [PanelSection(title: nil, rows: builtIn)] }
            return [
                PanelSection(title: "Built-in", rows: builtIn),
                PanelSection(title: "Add-ons", rows: session.addonSubtitles.map { addonRow($0, choice: choice) }),
            ]
        case .addonSubtitles(let addon):
            let files = session.addonSubtitles.first { $0.addon == addon }?.subtitles.value ?? []
            return languageGroups(files).map { group in
                let name = languageName(group.language)
                return PanelSection(title: name, rows: group.files.enumerated().map { index, file in
                    .choice(
                        file.label ?? "\(name) \(index + 1)",
                        isSelected: session.subtitleChoice == .addon(file.id), .chooseSubtitles(.addon(file.id))
                    )
                })
            }
        case .audio:
            return [PanelSection(title: nil, rows: state.tracks(.audio).map { .choice($0.label, isSelected: $0.isSelected, .select($0.id)) })]
        case .speed:
            return [PanelSection(title: nil, rows: PlaybackSpeed.allCases.map { .choice($0.label, isSelected: $0 == session.speed, .setSpeed($0)) })]
        }
    }

    /// An add-on's files open on their own page; until it has some, the row says why not.
    private func addonRow(_ source: SubtitleSource, choice: PlayerFeature.SubtitleChoice) -> PanelRow {
        switch source.subtitles {
        case .loading: return .note(source.addonName, detail: "Loading…")
        case .failed: return .note(source.addonName, detail: "Unavailable")
        case .loaded(let files) where files.isEmpty: return .note(source.addonName, detail: "None Found")
        case .loaded:
            let isChosen = if case .addon(let id) = choice { id.addon == source.addon } else { false }
            return .link(source.addonName, isSelected: isChosen, opens: .addonSubtitles(source.addon))
        }
    }

    /// Files grouped by language in the add-on's order, the preferred languages first.
    private func languageGroups(_ files: [AddonSubtitle]) -> [(language: String, files: [AddonSubtitle])] {
        var groups: [(language: String, files: [AddonSubtitle])] = []
        for file in files {
            if let index = groups.firstIndex(where: { $0.language == file.language }) {
                groups[index].files.append(file)
            } else {
                groups.append((file.language, [file]))
            }
        }
        let preferred = app.preferences.state.preferences?.languages.subtitles?.inPreferenceOrder ?? []
        for language in preferred.reversed() {
            if let index = groups.firstIndex(where: { Language($0.language) == language }) {
                groups.insert(groups.remove(at: index), at: 0)
            }
        }
        return groups
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
