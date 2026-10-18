import SwiftUI

@main
struct StremioApp: App {
    @State private var launch = Launch()

    var body: some Scene {
        WindowGroup {
            Group {
                switch launch.state {
                case .notStarted, .starting:
                    ProgressView("Starting…")
                case .ready(let app):
                    RootView().environment(app)
                case .failed(let error):
                    Label(error.description, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                }
            }
            .task { await launch.start() }
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 860)
        #endif
    }
}

enum StartupError: Error, CustomStringConvertible {
    case core(CoreError)
    case player(MPVEngine.StartError)

    var description: String {
        switch self {
        case .core(let error): "core failed to start: \(error)"
        case .player(let error): "mpv failed to start: \(error)"
        }
    }
}

/// The provider behind each port. Swapping a provider is a change here and nowhere else.
struct Services: Sendable {
    let account: any AccountService
    let addons: any AddonService
    let catalog: any CatalogService
    let streams: any StreamService
    let library: any LibraryService
    let preferences: any PreferencesService
    let tracker: any PlaybackTracker
    let engine: any PlaybackEngine
    let skipSegments: any SkipSegmentService

    @MainActor
    static func live(storageDirectory: URL) async throws(StartupError) -> Services {
        let core: CoreRuntime
        do {
            core = try await CoreRuntime.start(storageDirectory: storageDirectory)
        } catch {
            throw .core(error)
        }
        let engine: MPVEngine
        do {
            engine = try MPVEngine()
        } catch {
            throw .player(error)
        }
        return Services(
            account: CoreAccountService(runtime: core),
            addons: CoreAddonService(runtime: core),
            catalog: CoreCatalogService(runtime: core),
            streams: CoreStreamService(runtime: core),
            library: CoreLibraryService(runtime: core),
            preferences: CorePreferencesService(runtime: core),
            tracker: CorePlaybackTracker(runtime: core),
            engine: engine,
            skipSegments: SkipDBSkipSegmentService()
        )
    }
}

/// What screens use once the app has started: the services and the app-wide feature stores.
@MainActor
@Observable
final class AppContext {
    let services: Services
    let player: FeatureStore<PlayerFeature>
    let addons: FeatureStore<AddonsFeature>
    let streams: FeatureStore<StreamsFeature>
    let home: FeatureStore<HomeFeature>
    let account: FeatureStore<AccountFeature>
    let preferences: FeatureStore<PreferencesFeature>

    init(services: Services) {
        self.services = services
        player = FeatureStore(
            .idle,
            dependencies: PlayerFeature.Dependencies(
                engine: services.engine, tracker: services.tracker,
                skipSegments: services.skipSegments, preferences: services.preferences
            ),
            start: [.listen]
        )
        addons = FeatureStore(
            AddonsFeature.State(),
            dependencies: AddonsFeature.Dependencies(addons: services.addons),
            start: [.observeInstalled]
        )
        streams = FeatureStore(.idle, dependencies: StreamsFeature.Dependencies(streams: services.streams))
        home = FeatureStore(
            HomeFeature.State(),
            dependencies: HomeFeature.Dependencies(library: services.library, catalog: services.catalog),
            start: [.observeContinueWatching, .observeBoard]
        )
        account = FeatureStore(
            AccountFeature.State(),
            dependencies: AccountFeature.Dependencies(account: services.account),
            start: [.observeAccount]
        )
        preferences = FeatureStore(
            PreferencesFeature.State(),
            dependencies: PreferencesFeature.Dependencies(preferences: services.preferences),
            start: [.observePlayback]
        )
    }
}

/// Starts the services once per process. Screens exist only after it succeeds.
@MainActor
@Observable
final class Launch {
    enum State {
        case notStarted
        case starting
        case ready(AppContext)
        case failed(StartupError)
    }

    private(set) var state = State.notStarted

    func start() async {
        guard case .notStarted = state else { return }
        state = .starting
        let info = Bundle.main.infoDictionary
        Log.app.info("launch \(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?")), log file \(Log.fileURL.path)")
        let app: AppContext
        do {
            app = AppContext(services: try await Services.live(storageDirectory: Self.storageDirectory))
        } catch {
            Log.app.error("\(error)")
            state = .failed(error)
            return
        }
        state = .ready(app)
        Log.core.info("core ready")
        if let smoke = SmokeTest.Configuration(options: LaunchOptions.current) {
            await SmokeTest(configuration: smoke, app: app).run()
        }
    }

    /// `STREMIO_STORAGE_DIRECTORY` overrides it, so the smoke test runs against a fresh profile.
    private static var storageDirectory: URL {
        if let override = LaunchOptions.current["STREMIO_STORAGE_DIRECTORY"] {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        #if os(macOS)
        return URL.applicationSupportDirectory.appending(path: "\(Bundle.main.bundleIdentifier ?? "stremio")/core")
        #else
        return URL.cachesDirectory.appending(path: "core")
        #endif
    }
}
