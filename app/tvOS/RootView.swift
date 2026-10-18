import SwiftUI

/// Diagnostic screen for tvOS: core status, add-ons, stream lookup and full-screen playback.
/// Placeholder until the real UI is designed.
struct RootView: View {
    @Environment(PlaybackSession.self) private var playback

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
            get: { playback.stream != nil },
            set: { presented in
                if !presented { playback.stop() }
            }
        )
    }
}

private struct CoreStatusSection: View {
    @Environment(CoreStore.self) private var core

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Core").font(.headline)
            switch core.status {
            case .starting: Label("Starting…", systemImage: "hourglass")
            case .ready: Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    .accessibilityIdentifier("core.ready")
            case .failed(let message): Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            }
            Text("Account: \(core.ctx?.profile.auth?.user.email ?? "anonymous")")
                .foregroundStyle(.secondary)
        }
    }
}

private struct AddonsSection: View {
    @Environment(CoreStore.self) private var core
    @State private var url = ""
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add-ons").font(.headline)
            ForEach(core.ctx?.profile.addons ?? []) { addon in
                Text("\(addon.manifest.name) \(addon.manifest.version)").font(.callout)
            }
            TextField("Manifest URL", text: $url)
                .onSubmit(install)
                .accessibilityIdentifier("addons.manifestURL")
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("addons.status")
            }
        }
    }

    private func install() {
        guard let transportURL = URL(string: url.trimmingCharacters(in: .whitespaces)), core.status == .ready else { return }
        message = "Installing…"
        Task {
            do {
                let addon = try await core.installAddon(from: transportURL)
                message = "Installed \(addon.manifest.name)"
                url = ""
            } catch {
                Log.ui.error("install failed: \(error)")
                message = "\(error)"
            }
        }
    }
}

private struct ContinueWatchingSection: View {
    @Environment(CoreStore.self) private var core

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue watching").font(.headline)
            ForEach(core.continueWatching?.items ?? [], id: \.id) { item in
                Text("\(item.name) · \(item.state.timeOffset / 1000)s / \(item.state.duration / 1000)s").font(.callout)
                    .accessibilityIdentifier("continueWatching.item")
            }
        }
    }
}

private struct StreamsSection: View {
    @Environment(CoreStore.self) private var core
    @Environment(PlaybackSession.self) private var playback
    @State private var id = "tt0111161"
    @State private var groups: [StreamGroup] = []
    @State private var message: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                TextField("IMDb id (series: tt0944947:1:1)", text: $id)
                    .accessibilityIdentifier("streams.itemID")
                Button("Movie") { load(type: "movie") }
                    .accessibilityIdentifier("streams.findMovie")
                Button("Series") { load(type: "series") }
                    .accessibilityIdentifier("streams.findSeries")
            }
            .disabled(isLoading || core.status != .ready)
            .focusSection()
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("streams.status")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(groups) { group in
                        Text("\(group.addonName) (\(group.streams.count))").font(.headline)
                        ForEach(Array(group.streams.enumerated()), id: \.offset) { _, stream in
                            StreamRow(stream: stream) {
                                playback.play(stream, streamRequest: group.request, metaRequest: core.metaRequest)
                            }
                        }
                    }
                }
            }
        }
    }

    private func load(type: String) {
        isLoading = true
        message = "Loading…"
        Task {
            do {
                groups = try await core.loadStreams(type: type, id: id.trimmingCharacters(in: .whitespaces))
                message = "\(groups.map(\.streams.count).reduce(0, +)) streams from \(groups.count) add-ons"
            } catch {
                Log.ui.error("load streams failed: \(error)")
                message = "\(error)"
            }
            isLoading = false
        }
    }
}

private struct StreamRow: View {
    let stream: Stream
    let play: () -> Void

    var body: some View {
        // Unplayable streams are plain text, not disabled buttons: disabled buttons inside the
        // scroll view swallow "up" presses, so focus could never leave the list.
        switch stream.source {
        case .url:
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
            Text(stream.name ?? "Unnamed").font(.callout).bold()
            Text(stream.description ?? stream.filename ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

/// Full-screen playback. Remote: select or play/pause toggles pause, left/right seeks 10 s, Menu stops.
private struct PlayerScreen: View {
    @Environment(PlaybackSession.self) private var playback

    var body: some View {
        let player = playback.player
        ZStack(alignment: .bottomLeading) {
            Color.black
            if let layer = player.videoLayer {
                MPVVideoView(layer: layer)
            }
            if player.isBuffering {
                ProgressView()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(playback.stream?.name ?? "").font(.headline)
                Text("\(format(player.position)) / \(format(player.duration)) · \(statusText(player))")
                    .font(.caption).monospacedDigit()
                    .accessibilityIdentifier("player.status")
            }
            .padding(40)
            .opacity(player.phase == .playing ? 0.4 : 1)
        }
        .ignoresSafeArea()
        .focusable()
        .onTapGesture { player.togglePause() }
        .onPlayPauseCommand { player.togglePause() }
        .onMoveCommand { direction in
            switch direction {
            case .left: player.seek(by: -10)
            case .right: player.seek(by: 10)
            default: break
            }
        }
        .onExitCommand { playback.stop() }
    }

    private func statusText(_ player: PlayerController) -> String {
        var parts = ["\(player.phase)"]
        if let size = player.videoSize { parts.append("\(size.width)×\(size.height)") }
        if let decoder = player.hardwareDecoder { parts.append("hwdec \(decoder)") }
        return parts.joined(separator: " · ")
    }

    private func format(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}
