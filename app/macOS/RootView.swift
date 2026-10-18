import SwiftUI

/// Diagnostic screen proving the foundation works: core status, addons, stream lookup and playback.
/// Placeholder until the real UI is designed.
struct RootView: View {
    @Environment(CoreStore.self) private var core

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                CoreStatusSection()
                AddonsSection()
                ContinueWatchingSection()
                EventsSection()
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
    @Environment(CoreStore.self) private var core

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Core").font(.headline)
            switch core.status {
            case .starting: Label("Starting…", systemImage: "hourglass")
            case .ready: Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let message): Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            }
            Text("Account: \(core.ctx?.profile.auth?.user.email ?? "anonymous")")
                .foregroundStyle(.secondary)
            Button("Reveal log file") {
                NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL])
            }
        }
    }
}

private struct AddonsSection: View {
    @Environment(CoreStore.self) private var core
    @State private var url = ""
    @State private var message: String?
    @State private var isInstalling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add-ons").font(.headline)
            ForEach(core.ctx?.profile.addons ?? []) { addon in
                Text("\(addon.manifest.name) \(addon.manifest.version)")
                    .help(addon.transportUrl.absoluteString)
            }
            HStack {
                TextField("Manifest URL", text: $url)
                Button("Install", action: install)
                    .disabled(isInstalling || URL(string: url) == nil || core.status != .ready)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func install() {
        guard let transportURL = URL(string: url.trimmingCharacters(in: .whitespaces)) else { return }
        isInstalling = true
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
            isInstalling = false
        }
    }
}

private struct ContinueWatchingSection: View {
    @Environment(CoreStore.self) private var core

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Continue watching").font(.headline)
            ForEach(core.continueWatching?.items ?? [], id: \.id) { item in
                let state = item.state
                Text("\(item.name) · \(state.timeOffset / 1000)s / \(state.duration / 1000)s")
            }
        }
    }
}

private struct EventsSection: View {
    @Environment(CoreStore.self) private var core

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Core events").font(.headline)
            List(core.events.reversed()) { event in
                VStack(alignment: .leading) {
                    Text(event.name).bold()
                    Text(event.payload.compactDescription).font(.caption.monospaced()).lineLimit(3)
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct StreamsSection: View {
    @Environment(CoreStore.self) private var core
    @Environment(PlaybackSession.self) private var playback
    @State private var type = "movie"
    @State private var id = "tt0111161"
    @State private var groups: [StreamGroup] = []
    @State private var message: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Type", selection: $type) {
                    Text("Movie").tag("movie")
                    Text("Series").tag("series")
                }
                .frame(width: 160)
                TextField("IMDb id (series: tt0944947:1:1)", text: $id)
                Button("Find streams", action: load)
                    .disabled(isLoading || id.isEmpty || core.status != .ready)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            List {
                ForEach(groups) { group in
                    Section("\(group.addonName) (\(group.streams.count))") {
                        ForEach(Array(group.streams.enumerated()), id: \.offset) { _, stream in
                            StreamRow(stream: stream) {
                                playback.play(stream, streamRequest: group.request, metaRequest: core.metaRequest)
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func load() {
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stream.name ?? "Unnamed").bold()
                Text(stream.description ?? stream.filename ?? "").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch stream.source {
            case .url: Button("Play", action: play)
            case .unsupported(let kind): Text(kind).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct PlayerSection: View {
    @Environment(PlaybackSession.self) private var playback
    @Environment(CoreStore.self) private var core

    var body: some View {
        let player = playback.player
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let layer = player.videoLayer {
                    MPVVideoView(layer: layer)
                }
                if player.isBuffering {
                    ProgressView().controlSize(.large)
                }
            }
            HStack(spacing: 12) {
                Button(player.phase == .paused ? "Play" : "Pause") { player.togglePause() }
                Button("−10s") { player.seek(by: -10) }
                Button("+10s") { player.seek(by: 10) }
                Button("Stop") { playback.stop() }
                Text("\(format(player.position)) / \(format(player.duration))").monospacedDigit()
                Spacer()
                Text(statusText(player)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private func statusText(_ player: PlayerController) -> String {
        var parts = ["\(player.phase)"]
        if let size = player.videoSize { parts.append("\(size.width)×\(size.height)") }
        if let decoder = player.hardwareDecoder { parts.append("hwdec \(decoder)") }
        if let offset = core.player?.libraryItem?.state.timeOffset { parts.append("core offset \(offset / 1000)s") }
        return parts.joined(separator: " · ")
    }

    private func format(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}
