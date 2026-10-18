import SwiftUI

@main
struct StremioApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services.core)
                .environment(services.playback)
                .task { await services.launch() }
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 860)
        #endif
    }
}

/// The app's long-lived objects. One instance per process.
@MainActor
final class AppServices {
    let core = CoreStore()
    let playback: PlaybackSession

    init() {
        playback = PlaybackSession(core: core, player: PlayerController())
        let info = Bundle.main.infoDictionary
        Log.app.info("launch \(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?")), log file \(Log.fileURL.path)")
    }

    func launch() async {
        await core.start(storageDirectory: Self.storageDirectory)
        if let smoke = SmokeTest.Configuration(options: LaunchOptions.current) {
            await SmokeTest(configuration: smoke, core: core, playback: playback).run()
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
