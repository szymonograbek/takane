import SwiftUI

/// Diagnostic screen for tvOS: core status, add-ons, stream lookup and full-screen playback.
/// Placeholder until the real UI is designed.
struct RootView: View {
    @Environment(AppContext.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            VStack(alignment: .leading, spacing: 40) {
                CoreStatusSection()
                AddonsSection()
                ContinueWatchingSection()
            }
            .frame(width: 640, alignment: .leading)
            // Focus sections let the remote move between columns whose controls don't line up.
            .focusSection()

            StreamsSection()
                .focusSection()
        }
        .padding(60)
        .fullScreenCover(isPresented: isPlaying) {
            PlayerScreen()
        }
    }

    private var isPlaying: Binding<Bool> {
        Binding(
            get: { app.player.state.candidate != nil },
            set: { presented in
                if !presented { app.player.send(.stop) }
            }
        )
    }
}

private struct CoreStatusSection: View {
    @Environment(AppContext.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Core").font(.headline)
            Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                .accessibilityIdentifier("core.ready")
            Text("Account: \(app.overview.state.account.label)")
                .foregroundStyle(.secondary)
        }
    }
}

private struct AddonsSection: View {
    @Environment(AppContext.self) private var app
    @State private var url = ""

    var body: some View {
        let state = app.addons.state
        VStack(alignment: .leading, spacing: 8) {
            Text("Add-ons").font(.headline)
            ForEach(state.installed) { addon in
                Text("\(addon.name) \(addon.version)").font(.callout)
            }
            TextField("Manifest URL", text: $url)
                .onSubmit {
                    guard let manifest = ManifestURL(url) else { return }
                    app.addons.send(.install(manifest))
                }
                .accessibilityIdentifier("addons.manifestURL")
            if let message = state.install.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("addons.status")
            }
        }
        .onChange(of: state.install) { _, install in
            if case .installed = install { url = "" }
        }
    }
}

private struct ContinueWatchingSection: View {
    @Environment(AppContext.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue watching").font(.headline)
            ForEach(app.overview.state.continueWatching) { item in
                Text(item.progressLabel).font(.callout)
                    .accessibilityIdentifier("continueWatching.item")
            }
        }
    }
}

private struct StreamsSection: View {
    @Environment(AppContext.self) private var app
    @State private var id = "tt0111161"

    var body: some View {
        let state = app.streams.state
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                TextField("IMDb id (series: tt0944947:1:1)", text: $id)
                    .accessibilityIdentifier("streams.itemID")
                Button("Movie") { lookUp(kind: "movie") }
                    .accessibilityIdentifier("streams.findMovie")
                Button("Series") { lookUp(kind: "series") }
                    .accessibilityIdentifier("streams.findSeries")
            }
            .disabled(state.isLookingUp)
            .focusSection()
            if let message = state.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("streams.status")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(state.loadedSources) { source in
                        Text("\(source.addonName) (\(source.candidates.count))").font(.headline)
                        ForEach(source.candidates) { candidate in
                            StreamRow(candidate: candidate) { app.player.send(.open(candidate)) }
                        }
                    }
                }
            }
        }
    }

    private func lookUp(kind: String) {
        guard let item = PlayableID(id.trimmingCharacters(in: .whitespaces)), item.coreType == kind else {
            Log.ui.warning("not a \(kind) id: \(id)")
            return
        }
        app.streams.send(.lookUp(item))
    }
}

private struct StreamRow: View {
    let candidate: StreamCandidate
    let play: () -> Void

    var body: some View {
        // Unplayable streams are plain text, not disabled buttons: disabled buttons inside the
        // scroll view swallow "up" presses, so focus could never leave the list.
        switch candidate.playability {
        case .playable:
            Button(action: play) {
                details.frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("streams.row")
        case .unsupported(let kind):
            VStack(alignment: .leading, spacing: 4) {
                details
                Text("\(kind), not playable").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 30)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("streams.unplayableRow")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(candidate.name ?? "Unnamed").font(.callout).bold()
            Text(candidate.description ?? candidate.filename ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

/// Full-screen playback. Remote: select or play/pause toggles pause, left/right seeks 10 s, Menu stops.
private struct PlayerScreen: View {
    @Environment(AppContext.self) private var app

    var body: some View {
        let player = app.player
        let session = player.state.session
        ZStack(alignment: .bottomLeading) {
            Color.black
            VideoSurfaceView(layer: app.services.engine.surface)
            if session?.isBuffering == true {
                ProgressView()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(player.state.candidate?.name ?? "").font(.headline)
                Text(player.state.statusLine)
                    .font(.caption).monospacedDigit()
                    .accessibilityIdentifier("player.status")
            }
            .padding(40)
            .opacity(session?.phase == .playing ? 0.4 : 1)
        }
        .ignoresSafeArea()
        .focusable()
        .onTapGesture { player.send(.togglePause) }
        .onPlayPauseCommand { player.send(.togglePause) }
        .onMoveCommand { direction in
            switch direction {
            case .left: player.send(.seek(by: .seconds(-10)))
            case .right: player.send(.seek(by: .seconds(10)))
            default: break
            }
        }
        .onExitCommand { player.send(.stop) }
    }
}
