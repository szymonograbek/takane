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
            ProgressLine(fraction: session.duration > .zero ? session.position / session.duration : 0)
            HStack {
                Text(session.position.clock)
                Spacer()
                Text("−" + (session.duration - session.position).clock)
            }
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            HStack(spacing: 20) {
                transportButtons
                Spacer()
                SubtitleMenu(tracks: state.tracks(.subtitle), interacted: interacted)
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

private struct SubtitleMenu: View {
    @Environment(AppContext.self) private var app
    let tracks: [MediaTrack]
    let interacted: () -> Void

    var body: some View {
        Menu {
            Picker("Subtitles", selection: Binding(get: { tracks.first(where: \.isSelected)?.id }, set: choose)) {
                Text("Off").tag(MediaTrack.ID?.none)
                ForEach(tracks) { Text($0.label).tag(Optional($0.id)) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Subtitles", systemImage: "captions.bubble").labelStyle(.iconOnly)
        }
        .accessibilityIdentifier("player.subtitles")
    }

    private func choose(_ track: MediaTrack.ID?) {
        app.player.send(track.map(PlayerFeature.Event.select) ?? .turnOffSubtitles)
        interacted()
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
        let language = language.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }
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

extension PlaybackSpeed {
    var label: String {
        rawValue == 1 ? "Normal" : "\(rawValue.formatted())×"
    }
}
