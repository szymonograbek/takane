import Foundation
import ImageIO
import UniformTypeIdentifiers

/// End-to-end check of the running app: browse, search and describe titles from the default
/// add-ons, install an addon through core, resolve streams, play one, and confirm core
/// recorded progress.
///
/// Enabled by `LaunchOptions` (see scripts/smoke.sh):
/// - `STREMIO_SMOKE_ADDON_URL`: addon manifest URL (required to run)
/// - `STREMIO_SMOKE_ITEM`: `type/id`, default `movie/tt0063350`
/// - `STREMIO_SMOKE_SUBTITLES_ADDON_URL`: a subtitles add-on to install; the journey then waits for its
///   files for the stream playing and plays the first one
/// - `STREMIO_SMOKE_EXIT=1`: quit when done, exit code 0 on pass
/// - `STREMIO_SMOKE_CATALOG_EMPTY=1`: instead, check that a profile without add-ons lists only Open Movies'
///   catalog and reports no search or metadata add-ons, then that installing Cinemeta fills the board (core starts
///   without its default add-ons under `EMPTY_OFFICIAL_ADDONS=1`)
///
/// Writes `smoke-result.json`, `smoke-frame.png` and `smoke-export.log` next to the log file.
@MainActor
struct SmokeTest {
    struct Configuration {
        let manifest: ManifestURL
        let subtitlesManifest: ManifestURL?
        let item: PlayableID
        let exitWhenDone: Bool
        let expectsNoAddons: Bool

        init?(options: [String: String]) {
            guard let addon = options["STREMIO_SMOKE_ADDON_URL"], let manifest = ManifestURL(addon) else { return nil }
            let parts = (options["STREMIO_SMOKE_ITEM"] ?? "movie/tt0063350").split(separator: "/", maxSplits: 1)
            guard parts.count == 2, let item = PlayableID(String(parts[1])), item.coreType == parts[0] else { return nil }
            self.manifest = manifest
            self.subtitlesManifest = options["STREMIO_SMOKE_SUBTITLES_ADDON_URL"].flatMap { ManifestURL($0) }
            self.item = item
            self.exitWhenDone = options["STREMIO_SMOKE_EXIT"] == "1"
            self.expectsNoAddons = options["STREMIO_SMOKE_CATALOG_EMPTY"] == "1"
        }
    }

    enum Failure: Error, CustomStringConvertible {
        case addon(AddonError)
        case catalog(String)
        case details(DetailsError)
        case noPlayableStream(addon: Redacted<String>, groups: [String: Int])
        case noSubtitles(addon: Redacted<String>, SubtitleSourceError?)
        case player(PlaybackError)
        case noAudioOutput([String: String])
        case timedOut(String)

        var description: String {
            switch self {
            case .addon(let error): "addon: \(error)"
            case .catalog(let problem): "catalog: \(problem)"
            case .details(let error): "details: \(error)"
            case .noPlayableStream(let addon, let groups): "no playable stream from \(addon); groups: \(groups)"
            case .noSubtitles(let addon, let error): "no subtitles from \(addon): \(error.map(String.init(describing:)) ?? "none found")"
            case .player(let error): "player failed: \(error)"
            case .noAudioOutput(let output): "no audio output: \(output)"
            case .timedOut(let what): "timed out waiting for \(what)"
            }
        }
    }

    struct CatalogResult: Encodable {
        /// `rows` or `noCatalogAddons`.
        var board: String?
        var boardRows: Int?
        /// With `STREMIO_SMOKE_CATALOG_EMPTY=1`, after installing Cinemeta into the empty profile.
        var boardRowsAfterInstall: Int?
        var pagedRow: String?
        var pagedRowItems: Int?
        var pagedRowItemsAfterLoadMore: Int?
        /// `rows` or `noSearchAddons`.
        var search: String?
        var searchRows: Int?
        var searchHitRow: String?
        /// The title's name, or the error.
        var details: String?
        var detailsVideos: Int?
    }

    struct Result: Encodable {
        var passed = false
        var failure: String?
        var catalog = CatalogResult()
        var addon: String?
        var streamGroups: [String: Int] = [:]
        var playedStream: String?
        var playedURLHost: String?
        /// Files found per subtitles add-on, built-in tracks under "built-in".
        var subtitleCounts: [String: Int] = [:]
        var subtitleLabels: [String] = []
        var playedSubtitle: String?
        var videoSize: String?
        var decoder: String?
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
        Log.smoke.info("SMOKE start: addon=\(configuration.manifest) item=\(configuration.item.coreType)/\(configuration.item)")
        do {
            if configuration.expectsNoAddons {
                try await noAddonSteps(&result.catalog)
                try await firstCatalogAddonSteps(&result.catalog)
            } else {
                try await catalogSteps(&result.catalog)
                try await steps(&result)
            }
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

    private func install(_ manifest: ManifestURL) async throws(Failure) -> InstalledAddon {
        app.addons.send(.install(manifest))
        return try await app.addons.until(timeout: .seconds(45), onTimeout: Failure.timedOut("addon install")) { state in
            switch state.install {
            case .installed(let addon) where addon.manifestURL == manifest: .done(addon)
            case .failed(let failed, let error) where failed == manifest: .failed(Failure.addon(error))
            case .idle, .installing, .installed, .failed: .pending
            }
        }
    }

    private func steps(_ result: inout Result) async throws(Failure) {
        let manifest = configuration.manifest
        let addon = try await install(manifest)
        result.addon = "\(addon.name.rawValue) \(addon.version)"
        if let subtitles = configuration.subtitlesManifest {
            let installed = try await install(subtitles)
            Log.smoke.info("SMOKE subtitles addon installed: \(installed.name) \(installed.version)")
        }
        Log.smoke.info("SMOKE step 1/4 addon installed: \(addon.name) \(addon.version)")

        let item = configuration.item
        app.streams.send(.lookUp(item, account: app.account.state.account))
        let streams = try await app.streams.until(timeout: .seconds(60), onTimeout: Failure.timedOut("streams for \(item)")) { state in
            guard case .lookingUp(item, let results?, _) = state, results.isComplete else { return Probe<StreamResults, Failure>.pending }
            return .done(results)
        }
        let loaded = streams.sources.compactMap { source in source.candidates.value.map { (source, $0) } }
        result.streamGroups = Dictionary(loaded.map { ($0.0.addonName.rawValue, $0.1.count) }, uniquingKeysWith: +)
        guard let candidate = loaded.first(where: { $0.0.addon == manifest })?.1.first(where: { $0.source != nil }),
              let source = candidate.source
        else { throw .noPlayableStream(addon: addon.name, groups: result.streamGroups) }
        result.playedStream = [candidate.name, candidate.filename ?? candidate.description].compactMap { $0?.rawValue }.joined(separator: " | ")
        result.playedURLHost = source.url.rawValue.host()
        Log.smoke.info("SMOKE step 2/4 streams resolved: \(loaded.map { "\($0.0.addonName): \($0.1.count)" }); playing \(candidate.item)")

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
        result.decoder = session.decoder
        result.playbackPositionSeconds = session.position.seconds
        result.durationSeconds = session.duration.seconds
        Log.smoke.info(
            "SMOKE step 3/4 playing: \(session.position) of \(session.duration), \(result.videoSize ?? "?"), decoder=\(session.decoder ?? "none")"
        )
        if let subtitles = configuration.subtitlesManifest { try await subtitleSteps(subtitles, &result) }
        let engine = app.services.engine
        result.output = engine.diagnostics()
        Log.smoke.info("SMOKE output: \(result.output.sorted { $0.key < $1.key })")
        guard let delivery = result.output["audioDelivery"], ["streamCopy", "bridged", "decoded", "playerManaged"].contains(delivery) else {
            throw .noAudioOutput(result.output)
        }
        result.frameSaved = await engine.snapshot().map { Self.writePNG($0, to: Self.outputDirectory.appending(path: "smoke-frame.png")) } ?? false

        // Pausing makes core push the player's library item into the library, which feeds continue watching.
        app.player.send(.togglePause)
        let offset = try await app.home.until(timeout: .seconds(10), onTimeout: Failure.timedOut("continue watching progress")) { state in
            guard case .partway(let watched, _)? = state.continueWatching.first(where: { $0.media == item.media })?.reason, watched >= .seconds(5) else {
                return Probe<Duration, Failure>.pending
            }
            return .done(watched)
        }
        result.continueWatchingTimeOffsetMs = UInt64(offset / .milliseconds(1))
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
}

// MARK: - Catalog journey

extension SmokeTest {
    private func catalogSteps(_ result: inout CatalogResult) async throws(Failure) {
        try await boardSteps(&result)
        try await searchAndDetailsSteps(&result)
    }

    private func boardSteps(_ result: inout CatalogResult) async throws(Failure) {
        let catalog = app.services.catalog
        let (rows, paged) = try await Self.until(catalog.board(), timeout: .seconds(45), "board rows") { board in
            switch board {
            case .loading: return Probe<([CatalogRow], CatalogRow), Failure>.pending
            case .noCatalogAddons: return .failed(.catalog("no catalog add-ons on a fresh profile"))
            case .rows(let rows):
                // Cinemeta pages reliably; Open Movies lists all its films at once.
                if let paged = rows.first(where: { $0.id.addon == Self.cinemeta && $0.canLoadMore }) {
                    switch paged.items {
                    case .loading: return .pending
                    case .failed(let error): return .failed(.catalog("\(paged.name): \(error)"))
                    case .loaded: return .done((rows, paged))
                    }
                }
                if rows.allSatisfy({ $0.items.value != nil }) { return .failed(.catalog("no Cinemeta row can load more")) }
                return .pending
            }
        }
        result.board = "rows"
        result.boardRows = rows.count
        result.pagedRow = "\(paged.addonName.rawValue) \(paged.name.rawValue) (\(paged.id.type))"
        let before = paged.items.value?.count ?? 0
        result.pagedRowItems = before
        Log.smoke.info("SMOKE catalog 1/4 board: \(rows.count) rows, \(paged.addonName) \(paged.name) (\(paged.id.type)) has \(before) items")

        let board = catalog.board()
        catalog.loadMore(paged.id)
        result.pagedRowItemsAfterLoadMore = try await Self.until(board, timeout: .seconds(30), "next page of \(paged.name)") { board in
            guard case .rows(let rows) = board, let count = rows.first(where: { $0.id == paged.id })?.items.value?.count, count > before else {
                return Probe<Int, Failure>.pending
            }
            return .done(count)
        }
        Log.smoke.info("SMOKE catalog 2/4 load more: \(before) -> \(result.pagedRowItemsAfterLoadMore ?? 0) items")
    }

    private func searchAndDetailsSteps(_ result: inout CatalogResult) async throws(Failure) {
        let catalog = app.services.catalog
        let query = try Self.parsed(SearchText("night of the living dead"))
        let searched = try Self.parsed(MediaID("tt0063350"))
        let show = try Self.parsed(MediaID("tt1748166"))
        let episode = PlayableID.episode(show, season: 1, episode: 1)

        let (searchRows, hit) = try await Self.until(catalog.search(query), timeout: .seconds(45), "search \(query)") { results in
            switch results {
            case .searching: return Probe<(Int, CatalogRow), Failure>.pending
            case .noSearchAddons: return .failed(.catalog("no search add-ons on a fresh profile"))
            case .rows(_, let rows):
                if let hit = rows.first(where: { $0.items.value?.contains { $0.media == searched } ?? false }) {
                    return .done((rows.count, hit))
                }
                return rows.allSatisfy(\.items.isSettled) ? .failed(.catalog("no search row has \(searched)")) : .pending
            }
        }
        result.search = "rows"
        result.searchRows = searchRows
        result.searchHitRow = "\(hit.addonName.rawValue) \(hit.name.rawValue) (\(hit.id.type))"
        Log.smoke.info("SMOKE catalog 3/4 search \(query): \(searchRows) rows, \(searched) in \(hit.addonName) \(hit.name) (\(hit.id.type))")

        let details: TitleDetails
        do {
            details = try await catalog.details(show, type: .series)
        } catch {
            throw .details(error)
        }
        result.details = details.preview.name.rawValue
        result.detailsVideos = details.videos.count
        guard details.preview.name.rawValue == "Pioneer One", details.videos.contains(where: { $0.playable == episode }) else {
            throw .catalog("details of \(show): \(details.preview.name) with \(details.videos.count) videos, no \(episode)")
        }
        Log.smoke.info("SMOKE catalog 4/4 details: \(details.preview.name), \(details.videos.count) videos incl. \(episode)")
    }

    private func noAddonSteps(_ result: inout CatalogResult) async throws(Failure) {
        let catalog = app.services.catalog
        let query = try Self.parsed(SearchText("night of the living dead"))
        let show = try Self.parsed(MediaID("tt1748166"))

        result.board = try await Self.until(catalog.board(), timeout: .seconds(15), "empty board") { board in
            switch board {
            case .loading: Probe<String, Failure>.pending
            case .noCatalogAddons: .done("noCatalogAddons")
            case .rows(let rows) where rows.allSatisfy({ $0.id.addon == Self.openMovies }): .done("Open Movies only")
            case .rows(let rows): .failed(.catalog("expected only Open Movies, got \(rows.count) rows"))
            }
        }
        result.search = try await Self.until(catalog.search(query), timeout: .seconds(15), "empty search") { results in
            switch results {
            case .searching: Probe<String, Failure>.pending
            case .noSearchAddons: .done("noSearchAddons")
            case .rows(_, let rows): .failed(.catalog("expected no search add-ons, got \(rows.count) rows"))
            }
        }
        let details: Swift.Result<TitleDetails, DetailsError>
        do {
            details = .success(try await catalog.details(show, type: .series))
        } catch {
            details = .failure(error)
        }
        switch details {
        case .failure(.noMetaAddons): result.details = "noMetaAddons"
        case .failure(let error): throw .details(error)
        case .success(let details): throw .catalog("expected no meta add-ons, got \(details.preview.name)")
        }
        Log.smoke.info("SMOKE no add-ons: board \(result.board ?? ""), search \(result.search ?? ""), details \(result.details ?? "")")
    }

    /// The board stream opened before the install must pick up the new add-on's rows by itself.
    private func firstCatalogAddonSteps(_ result: inout CatalogResult) async throws(Failure) {
        let cinemeta = try Self.parsed(Self.cinemeta)
        let board = app.services.catalog.board()
        app.addons.send(.install(cinemeta))
        let rows = try await Self.until(board, timeout: .seconds(45), "board rows after installing Cinemeta") { board in
            guard case .rows(let rows) = board,
                  rows.contains(where: { $0.id.addon != Self.openMovies && !($0.items.value ?? []).isEmpty }) else {
                return Probe<[CatalogRow], Failure>.pending
            }
            return .done(rows)
        }
        result.boardRowsAfterInstall = rows.count
        Log.smoke.info("SMOKE installed Cinemeta: board has \(rows.count) rows")
    }

    /// The add-on the bridge lists first on every signed-out profile, default add-ons or not.
    nonisolated private static let openMovies = ManifestURL("https://open-movies.invalid/manifest.json")
    nonisolated private static let cinemeta = ManifestURL("https://v3-cinemeta.strem.io/manifest.json")

    private static func parsed<Value>(_ value: Value?) throws(Failure) -> Value {
        guard let value else { throw .catalog("invalid smoke input") }
        return value
    }

    /// Waits until `probe` decides on a value of `values`.
    private static func until<Value: Sendable, Output: Sendable>(
        _ values: AsyncStream<Value>,
        timeout: Duration,
        _ what: String,
        _ probe: @escaping @Sendable (Value) -> Probe<Output, Failure>
    ) async throws(Failure) -> Output {
        let outcome = await withTaskGroup(of: Swift.Result<Output, Failure>.self) { group in
            group.addTask {
                for await value in values {
                    switch probe(value) {
                    case .pending: continue
                    case .done(let output): return .success(output)
                    case .failed(let failure): return .failure(failure)
                    }
                }
                return .failure(.catalog("\(what): stream finished"))
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .failure(.timedOut(what))
            }
            defer { group.cancelAll() }
            return await group.next() ?? .failure(.timedOut(what))
        }
        return try outcome.get()
    }
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
