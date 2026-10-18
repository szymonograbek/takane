import SwiftUI

/// Diagnostic screen proving the foundation works: core status, addons, stream lookup and playback.
/// Placeholder until the real UI is designed.
struct RootView: View {
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                CoreStatusSection()
                AddonsSection()
                ContinueWatchingSection()
                Spacer()
            }
            .padding()
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 480, maxHeight: .infinity, alignment: .top)

            VSplitView {
                PlayerSection()
                    .frame(minHeight: 280)
                StreamsSection()
                    .frame(minHeight: 200)
            }
            .frame(minWidth: 600)
        }
    }
}

private struct CoreStatusSection: View {
    @Environment(AppContext.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Core").font(.headline)
            Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Account: \(app.overview.state.account.label)")
                .foregroundStyle(.secondary)
            Button("Reveal log file") {
                NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL])
            }
        }
    }
}

private struct AddonsSection: View {
    @Environment(AppContext.self) private var app
    @State private var url = ""

    var body: some View {
        let state = app.addons.state
        VStack(alignment: .leading, spacing: 6) {
            Text("Add-ons").font(.headline)
            ForEach(state.installed) { addon in
                Text("\(addon.name) \(addon.version)")
                    .help(addon.manifestURL.description)
            }
            HStack {
                TextField("Manifest URL", text: $url)
                Button("Install") {
                    guard let manifest = ManifestURL(url) else { return }
                    app.addons.send(.install(manifest))
                }
                .disabled(ManifestURL(url) == nil || state.install.isInstalling)
            }
            if let message = state.install.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Continue watching").font(.headline)
            ForEach(app.overview.state.continueWatching) { item in
                Text(item.progressLabel)
            }
        }
    }
}

private struct StreamsSection: View {
    @Environment(AppContext.self) private var app
    @State private var kind = "movie"
    @State private var id = "tt0111161"

    var body: some View {
        let state = app.streams.state
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Type", selection: $kind) {
                    Text("Movie").tag("movie")
                    Text("Series").tag("series")
                }
                .frame(width: 160)
                TextField("IMDb id (series: tt0944947:1:1)", text: $id)
                Button("Find streams") {
                    guard let item else { return }
                    app.streams.send(.lookUp(item))
                }
                .disabled(state.isLookingUp || item == nil)
            }
            if let message = state.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            List {
                ForEach(state.loadedSources) { source in
                    Section("\(source.addonName) (\(source.candidates.count))") {
                        ForEach(source.candidates) { candidate in
                            StreamRow(candidate: candidate) { app.player.send(.open(candidate)) }
                        }
                    }
                }
            }
        }
        .padding()
    }

    private var item: PlayableID? {
        PlayableID(id.trimmingCharacters(in: .whitespaces)).flatMap { $0.coreType == kind ? $0 : nil }
    }
}

private struct StreamRow: View {
    let candidate: StreamCandidate
    let play: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name ?? "Unnamed").bold()
                Text(candidate.description ?? candidate.filename ?? "").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch candidate.playability {
            case .playable: Button("Play", action: play)
            case .unsupported(let kind): Text(kind).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct PlayerSection: View {
    @Environment(AppContext.self) private var app

    var body: some View {
        let player = app.player
        let session = player.state.session
        VStack(spacing: 0) {
            ZStack {
                Color.black
                VideoSurfaceView(layer: app.services.engine.surface)
                if session?.isBuffering == true {
                    ProgressView().controlSize(.large)
                }
            }
            HStack(spacing: 12) {
                Button(session?.phase == .paused ? "Play" : "Pause") { player.send(.togglePause) }
                Button("−10s") { player.send(.seek(by: .seconds(-10))) }
                Button("+10s") { player.send(.seek(by: .seconds(10))) }
                Button("Stop") { player.send(.stop) }
                Text(player.state.statusLine).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
            }
            .padding(8)
        }
    }
}
