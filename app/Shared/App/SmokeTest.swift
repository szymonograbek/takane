import Foundation
import ImageIO
import UniformTypeIdentifiers

/// End-to-end check of the running app: install an addon through core, resolve streams,
/// play one in mpv, and confirm core recorded progress.
///
/// Enabled by `LaunchOptions` (see scripts/smoke.sh):
/// - `STREMIO_SMOKE_ADDON_URL`: addon manifest URL (required to run)
/// - `STREMIO_SMOKE_ITEM`: `type/id`, default `movie/tt0111161`
/// - `STREMIO_SMOKE_EXIT=1`: quit when done, exit code 0 on pass
///
/// Writes `smoke-result.json` and `smoke-frame.png` next to the log file.
@MainActor
struct SmokeTest {
    struct Configuration {
        let addonURL: URL
        let type: String
        let id: String
        let exitWhenDone: Bool

        init?(options: [String: String]) {
            guard let addon = options["STREMIO_SMOKE_ADDON_URL"], let addonURL = URL(string: addon) else { return nil }
            let item = (options["STREMIO_SMOKE_ITEM"] ?? "movie/tt0111161").split(separator: "/", maxSplits: 1)
            guard item.count == 2 else { return nil }
            self.addonURL = addonURL
            self.type = String(item[0])
            self.id = String(item[1])
            self.exitWhenDone = options["STREMIO_SMOKE_EXIT"] == "1"
        }
    }

    private struct Result: Encodable {
        var passed = false
        var failure: String?
        var addon: String?
        var streamGroups: [String: Int] = [:]
        var playedStream: String?
        var playedURLHost: String?
        var videoSize: String?
        var hardwareDecoder: String?
        var playbackPositionSeconds: Double?
        var durationSeconds: Double?
        var continueWatchingTimeOffsetMs: UInt64?
        var frameSaved = false
        var output: [String: String] = [:]
        var elapsedSeconds: Double = 0
    }

    let configuration: Configuration
    let core: CoreStore
    let playback: PlaybackSession

    func run() async {
        let started = ContinuousClock.now
        var result = Result()
        Log.smoke.info("SMOKE start: addon=\(configuration.addonURL.host() ?? "?") item=\(configuration.type)/\(configuration.id)")
        do {
            try await core.waitUntil("core ready", timeout: .seconds(30)) { core.status == .ready ? true : nil }

            let addon = try await core.installAddon(from: configuration.addonURL)
            result.addon = "\(addon.manifest.name) \(addon.manifest.version)"
            Log.smoke.info("SMOKE step 1/4 addon installed: \(result.addon ?? "")")

            let groups = try await core.loadStreams(type: configuration.type, id: configuration.id)
            result.streamGroups = Dictionary(groups.map { ($0.addonName, $0.streams.count) }, uniquingKeysWith: +)
            guard let group = groups.first(where: { $0.request.base == addon.transportUrl }),
                  let stream = group.streams.first(where: { $0.playableURL != nil })
            else { throw WorkflowError(description: "no playable stream from \(addon.manifest.name); groups: \(result.streamGroups)") }
            result.playedStream = [stream.name, stream.filename ?? stream.description].compactMap { $0 }.joined(separator: " | ")
            result.playedURLHost = stream.playableURL?.host()
            Log.smoke.info("SMOKE step 2/4 streams resolved: \(result.streamGroups); playing \(result.playedStream ?? "")")

            playback.play(stream, streamRequest: group.request, metaRequest: core.metaRequest)
            let player = playback.player
            try await core.waitUntil("10s of playback", timeout: .seconds(90)) { () throws -> Bool? in
                if case .failed(let message) = player.phase { throw WorkflowError(description: "player failed: \(message)") }
                return player.phase == .playing && player.position >= 10 && player.videoSize != nil ? true : nil
            }
            result.videoSize = player.videoSize.map { "\($0.width)x\($0.height)" }
            result.hardwareDecoder = player.hardwareDecoder
            result.playbackPositionSeconds = player.position
            result.durationSeconds = player.duration
            Log.smoke.info("SMOKE step 3/4 playing: \(player.position)s of \(player.duration)s, \(result.videoSize ?? "?"), hwdec=\(player.hardwareDecoder ?? "none")")
            result.output = player.playbackDiagnostics()
            Log.smoke.info("SMOKE output: \(result.output.sorted { $0.key < $1.key })")
            guard result.output["current-ao"] != nil, result.output["audio-codec-name"] != nil else {
                throw WorkflowError(description: "no audio output: \(result.output)")
            }
            result.frameSaved = await player.snapshot().map { Self.writePNG($0, to: Self.outputDirectory.appending(path: "smoke-frame.png")) } ?? false

            // Pausing makes core push the player's library item into the library, which feeds continue watching.
            player.togglePause()
            let metaID = configuration.id.split(separator: ":").first.map(String.init) ?? configuration.id
            let offset = try await core.waitUntil("continue watching progress", timeout: .seconds(10)) { () -> UInt64? in
                guard let item = core.continueWatching?.items.first(where: { $0.id == metaID }),
                      item.state.timeOffset >= 5_000
                else { return nil }
                return item.state.timeOffset
            }
            result.continueWatchingTimeOffsetMs = offset
            Log.smoke.info("SMOKE step 4/4 continue watching has the item after pause: timeOffset=\(offset)ms")
            result.passed = true
        } catch {
            result.failure = "\(error)"
            Log.smoke.error("SMOKE FAIL: \(error)")
        }
        result.elapsedSeconds = (ContinuousClock.now - started).seconds
        if result.passed {
            Log.smoke.info("SMOKE PASS in \(result.elapsedSeconds)s")
        }
        write(result)

        if configuration.exitWhenDone {
            // Let the screenshot and log writes land before quitting.
            try? await Task.sleep(for: .seconds(2))
            playback.stop()
            exit(result.passed ? 0 : 1)
        }
    }

    static var outputDirectory: URL { Log.fileURL.deletingLastPathComponent() }

    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        let written = CGImageDestinationFinalize(destination)
        Log.smoke.write(written ? .info : .error) { "frame \(image.width)x\(image.height) written=\(written) to \(url.path)" }
        return written
    }

    private func write(_ result: Result) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let url = Self.outputDirectory.appending(path: "smoke-result.json")
        do {
            try encoder.encode(result).write(to: url)
            Log.smoke.info("SMOKE result written to \(url.path)")
        } catch {
            Log.smoke.error("SMOKE result write failed: \(error)")
        }
    }
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
