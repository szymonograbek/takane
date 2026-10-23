#if DEBUG
import Foundation

/// Plays one URL with its headers, no add-on involved, to check that every request the player makes
/// for a file on the user's own server carries its credentials. Debug builds only: the header holds a
/// password.
///
/// Enabled by `LaunchOptions` (see scripts/smoke.sh):
/// - `STREMIO_SMOKE_PLAY_URL`: the file to play (required to run)
/// - `STREMIO_SMOKE_PLAY_HEADER`: `Name: Value`, sent with every request for the file
/// - `STREMIO_SMOKE_PLAY_SUBTITLES`: a subtitle file to add once playing; the run waits for its first cue
/// - `STREMIO_SMOKE_EXIT=1`: quit when done, exit code 0 on pass
///
/// Plays 10 s, seeks to 60 s and plays on, then writes `smoke-result.json` and `smoke-frame.png`
/// next to the log file, as `SmokeTest` does.
@MainActor
struct DirectPlaySmoke {
    let candidate: StreamCandidate
    let source: PlaybackSource
    let subtitles: Redacted<URL>?
    let exitWhenDone: Bool
    let app: AppContext

    init?(options: [String: String], app: AppContext) {
        guard let text = options["STREMIO_SMOKE_PLAY_URL"], let url = URL(string: text),
              let addon = ManifestURL("https://direct-play.invalid/manifest.json"), let item = PlayableID("tt0000000")
        else { return nil }
        var headers: [String: String] = [:]
        if let header = options["STREMIO_SMOKE_PLAY_HEADER"], !header.isEmpty {
            let parts = header.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            headers[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        source = PlaybackSource(url: Redacted(url), headers: headers)
        // Core's tracker gets no selection, so this play leaves no trace in the library.
        candidate = StreamCandidate(
            id: StreamCandidate.ID(addon: addon, index: 0), item: item, name: nil, description: nil, filename: nil,
            playability: .playable(source), tracking: TrackingToken(payload: Redacted(.null))
        )
        subtitles = options["STREMIO_SMOKE_PLAY_SUBTITLES"].flatMap { URL(string: $0) }.map { Redacted($0) }
        exitWhenDone = options["STREMIO_SMOKE_EXIT"] == "1"
        self.app = app
    }

    func run() async {
        let started = ContinuousClock.now
        var result = SmokeTest.Result()
        Log.smoke.info("SMOKE direct play: \(source.url) headers=\(source.headers.keys.sorted())")
        do {
            try await steps(&result)
            result.passed = true
            Log.smoke.info("SMOKE PASS")
        } catch {
            result.failure = "\(error)"
            Log.smoke.error("SMOKE FAIL: \(error)")
        }
        result.elapsedSeconds = (ContinuousClock.now - started) / .seconds(1)
        SmokeTest.write(result)

        if exitWhenDone {
            // Let the screenshot and log writes land before quitting.
            try? await Task.sleep(for: .seconds(2))
            app.player.send(.stop)
            exit(result.passed ? 0 : 1)
        }
    }

    private func steps(_ result: inout SmokeTest.Result) async throws(SmokeTest.Failure) {
        let engine = app.services.engine
        result.playedURLHost = source.url.rawValue.host()
        app.player.send(.open(candidate))
        let session = try await playing(past: .seconds(3), "3s of playback")
        result.videoSize = session.videoSize.map { "\($0.width)x\($0.height)" }
        result.decoder = session.decoder
        result.durationSeconds = session.duration / .seconds(1)
        Log.smoke.info("SMOKE direct 1/3 playing: \(session.position) of \(session.duration), route=\(engine.diagnostics()["route"] ?? "?")")

        if let subtitles {
            engine.addSubtitles(subtitles, title: "Sidecar", language: "en")
            let track = try await app.player.until(timeout: .seconds(20), onTimeout: SmokeTest.Failure.timedOut("a cue from \(subtitles)")) { state in
                guard let session = state.session, !session.subtitles.isEmpty,
                      let track = session.tracks.first(where: { $0.externalFile == subtitles && $0.isSelected })
                else { return Probe<MediaTrack, SmokeTest.Failure>.pending }
                return .done(track)
            }
            result.playedSubtitle = "track \(track.id.number), cue on screen"
            Log.smoke.info("SMOKE direct 2/3 subtitles: track \(track.id.number) shows a cue")
        }

        _ = try await playing(past: .seconds(10), "10s of playback")
        engine.seek(to: .seconds(60))
        let seeked = try await playing(past: .seconds(63), "playback after seeking to 60s")
        result.playbackPositionSeconds = seeked.position / .seconds(1)
        result.output = engine.diagnostics()
        Log.smoke.info("SMOKE direct 3/3 seeked: \(seeked.position), output: \(result.output.sorted { $0.key < $1.key })")
        result.frameSaved = await engine.snapshot().map { SmokeTest.writePNG($0, to: SmokeTest.outputDirectory.appending(path: "smoke-frame.png")) } ?? false
    }

    private func playing(past position: Duration, _ what: String) async throws(SmokeTest.Failure) -> PlayerFeature.Session {
        try await app.player.until(timeout: .seconds(60), onTimeout: SmokeTest.Failure.timedOut(what)) { state in
            switch state {
            case .active(let session) where session.phase == .playing && session.position >= position && session.videoSize != nil:
                .done(session)
            case .failed(_, let error): .failed(SmokeTest.Failure.player(error))
            case .idle, .active: .pending
            }
        }
    }
}
#endif
