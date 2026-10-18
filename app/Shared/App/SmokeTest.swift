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
        let manifest: ManifestURL
        let item: PlayableID
        let exitWhenDone: Bool

        init?(options: [String: String]) {
            guard let addon = options["STREMIO_SMOKE_ADDON_URL"], let manifest = ManifestURL(addon) else { return nil }
            let parts = (options["STREMIO_SMOKE_ITEM"] ?? "movie/tt0111161").split(separator: "/", maxSplits: 1)
            guard parts.count == 2, let item = PlayableID(String(parts[1])), item.coreType == parts[0] else { return nil }
            self.manifest = manifest
            self.item = item
            self.exitWhenDone = options["STREMIO_SMOKE_EXIT"] == "1"
        }
    }

    private enum Failure: Error, CustomStringConvertible {
        case addon(AddonError)
        case noPlayableStream(addon: String, groups: [String: Int])
        case player(PlaybackError)
        case noAudioOutput([String: String])
        case timedOut(String)

        var description: String {
            switch self {
            case .addon(let error): "addon: \(error)"
            case .noPlayableStream(let addon, let groups): "no playable stream from \(addon); groups: \(groups)"
            case .player(let error): "player failed: \(error)"
            case .noAudioOutput(let output): "no audio output: \(output)"
            case .timedOut(let what): "timed out waiting for \(what)"
            }
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
    let app: AppContext

    func run() async {
        let started = ContinuousClock.now
        var result = Result()
        Log.smoke.info("SMOKE start: addon=\(configuration.manifest.url.host() ?? "?") item=\(configuration.item.coreType)/\(configuration.item)")
        do {
            try await steps(&result)
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
            app.player.send(.stop)
            exit(result.passed ? 0 : 1)
        }
    }

    private func steps(_ result: inout Result) async throws(Failure) {
        let manifest = configuration.manifest
        app.addons.send(.install(manifest))
        let addon = try await app.addons.until(timeout: .seconds(45), onTimeout: Failure.timedOut("addon install")) { state in
            switch state.install {
            case .installed(let addon) where addon.manifestURL == manifest: .done(addon)
            case .failed(let failed, let error) where failed == manifest: .failed(Failure.addon(error))
            case .idle, .installing, .installed, .failed: .pending
            }
        }
        result.addon = "\(addon.name) \(addon.version)"
        Log.smoke.info("SMOKE step 1/4 addon installed: \(result.addon ?? "")")

        let item = configuration.item
        app.streams.send(.lookUp(item))
        let streams = try await app.streams.until(timeout: .seconds(60), onTimeout: Failure.timedOut("streams for \(item)")) { state in
            guard case .lookingUp(item, let results?) = state, results.isComplete else { return Probe<StreamResults, Failure>.pending }
            return .done(results)
        }
        let loaded = streams.sources.compactMap { source in source.candidates.value.map { (source, $0) } }
        result.streamGroups = Dictionary(loaded.map { ($0.0.addonName, $0.1.count) }, uniquingKeysWith: +)
        guard let candidate = loaded.first(where: { $0.0.addon == manifest })?.1.first(where: { $0.source != nil }),
              let source = candidate.source
        else { throw .noPlayableStream(addon: addon.name, groups: result.streamGroups) }
        result.playedStream = [candidate.name, candidate.filename ?? candidate.description].compactMap { $0 }.joined(separator: " | ")
        result.playedURLHost = source.url.host()
        Log.smoke.info("SMOKE step 2/4 streams resolved: \(result.streamGroups); playing \(result.playedStream ?? "")")

        app.player.send(.open(candidate))
        let session = try await app.player.until(timeout: .seconds(90), onTimeout: Failure.timedOut("10s of playback")) { state in
            switch state {
            case .active(let session) where session.phase == .playing && session.position >= .seconds(10) && session.videoSize != nil:
                .done(session)
            case .failed(_, let error): .failed(Failure.player(error))
            case .idle, .active: .pending
            }
        }
        result.videoSize = session.videoSize.map { "\($0.width)x\($0.height)" }
        result.hardwareDecoder = session.hardwareDecoder
        result.playbackPositionSeconds = session.position.seconds
        result.durationSeconds = session.duration.seconds
        Log.smoke.info(
            "SMOKE step 3/4 playing: \(session.position) of \(session.duration), \(result.videoSize ?? "?"), hwdec=\(session.hardwareDecoder ?? "none")"
        )
        let engine = app.services.engine
        result.output = engine.diagnostics()
        Log.smoke.info("SMOKE output: \(result.output.sorted { $0.key < $1.key })")
        guard result.output["current-ao"] != nil, result.output["audio-codec-name"] != nil else {
            throw .noAudioOutput(result.output)
        }
        result.frameSaved = await engine.snapshot().map { Self.writePNG($0, to: Self.outputDirectory.appending(path: "smoke-frame.png")) } ?? false

        // Pausing makes core push the player's library item into the library, which feeds continue watching.
        app.player.send(.togglePause)
        let progress = try await app.overview.until(timeout: .seconds(10), onTimeout: Failure.timedOut("continue watching progress")) { state in
            guard let watched = state.continueWatching.first(where: { $0.media == item.media }), watched.offset >= .seconds(5) else {
                return Probe<ContinueWatchingItem, Failure>.pending
            }
            return .done(watched)
        }
        result.continueWatchingTimeOffsetMs = UInt64(progress.offset / .milliseconds(1))
        Log.smoke.info("SMOKE step 4/4 continue watching has the item after pause: timeOffset=\(result.continueWatchingTimeOffsetMs ?? 0)ms")
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
