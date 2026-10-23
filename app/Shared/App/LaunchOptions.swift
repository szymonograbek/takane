import Foundation

/// `STREMIO_*` settings for a launch, from environment variables or from launch arguments
/// (`-STREMIO_STORAGE_DIRECTORY /path`). Arguments exist for UI drivers such as agent-device,
/// which forward process arguments but not environment variables. The environment wins.
enum LaunchOptions {
    static let current: [String: String] = {
        // The arguments as given: the user defaults' argument domain parses a value that looks like
        // a property list, such as `STREMIO_SOURCES`' JSON, into one, which is no longer the text.
        var arguments: [String: String] = [:]
        var rest = ProcessInfo.processInfo.arguments.dropFirst()
        while let argument = rest.popFirst() {
            guard argument.hasPrefix("-STREMIO_"), let value = rest.first else { continue }
            arguments[String(argument.dropFirst())] = value
            rest.removeFirst()
        }
        return arguments.merging(ProcessInfo.processInfo.environment) { _, environment in environment }
    }()
}
