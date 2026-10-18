import Foundation

/// `STREMIO_*` settings for a launch, from environment variables or from launch arguments
/// (`-STREMIO_STORAGE_DIRECTORY /path`). Arguments exist for UI drivers such as agent-device,
/// which forward process arguments but not environment variables. The environment wins.
enum LaunchOptions {
    static let current: [String: String] = {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            .compactMapValues { $0 as? String }
            .filter { $0.key.hasPrefix("STREMIO_") }
        return arguments.merging(ProcessInfo.processInfo.environment) { _, environment in environment }
    }()
}
