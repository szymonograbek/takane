import Foundation
import os

/// App-wide logging. Every line goes to the unified log (subsystem = bundle id, one category
/// per `Log` instance) and to a plain-text file. In debug builds it is also echoed to stderr.
///
/// Usage: `Log.player.debug("loaded \(url)")`.
/// Read logs with `tail -f "<Log.fileURL>"` or Console.app filtered by subsystem.
/// Long opaque tokens (debrid API keys, add-on configs, playback ids, ≥32 URL-safe characters)
/// are masked in every line, because add-ons carry credentials inside their URLs.
/// The minimum level comes from the `STREMIO_LOG_LEVEL` launch option (see `LaunchOptions`) (`trace` … `error`),
/// defaulting to `debug`.
struct Log: Sendable {
    enum Level: Int, Comparable, Sendable {
        case trace, debug, info, warning, error

        init?(name: String) {
            switch name.lowercased() {
            case "trace": self = .trace
            case "debug": self = .debug
            case "info": self = .info
            case "warning", "warn": self = .warning
            case "error": self = .error
            default: return nil
            }
        }

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .trace: "TRACE"
            case .debug: "DEBUG"
            case .info: "INFO "
            case .warning: "WARN "
            case .error: "ERROR"
            }
        }
    }

    static let app = Log(category: "app")
    static let core = Log(category: "core")
    static let network = Log(category: "network")
    static let player = Log(category: "player")
    static let ui = Log(category: "ui")
    static let features = Log(category: "features")
    static let smoke = Log(category: "smoke")

    /// Messages forwarded from Rust keep their Rust module path as the category.
    static func rust(target: String) -> Log { Log(category: "rust:\(target)") }

    static var fileURL: URL { LogSink.shared.fileURL }

    let category: String
    private let osLogger: Logger

    init(category: String) {
        self.category = category
        self.osLogger = Logger(subsystem: LogSink.subsystem, category: category)
    }

    func trace(_ message: @autoclosure () -> String) { write(.trace, message) }
    func debug(_ message: @autoclosure () -> String) { write(.debug, message) }
    func info(_ message: @autoclosure () -> String) { write(.info, message) }
    func warning(_ message: @autoclosure () -> String) { write(.warning, message) }
    func error(_ message: @autoclosure () -> String) { write(.error, message) }

    // Regex is immutable once built but not declared Sendable.
    // swiftlint:disable:next nonisolated_unsafe
    nonisolated(unsafe) private static let secretPattern = /[A-Za-z0-9_\-]{32,}/

    /// Keeps the first 4 characters of each token so lines stay correlatable.
    static func redactingSecrets(_ text: String) -> String {
        text.replacing(secretPattern) { match in "\(match.output.prefix(4))…[redacted]" }
    }

    func write(_ level: Level, _ message: () -> String) {
        guard level >= LogSink.shared.minimumLevel else { return }
        let text = Self.redactingSecrets(message())
        switch level {
        case .trace, .debug: osLogger.debug("\(text, privacy: .public)")
        case .info: osLogger.info("\(text, privacy: .public)")
        case .warning: osLogger.warning("\(text, privacy: .public)")
        case .error: osLogger.error("\(text, privacy: .public)")
        }
        LogSink.shared.append(level: level, category: category, message: text)
    }
}

/// Serializes file (and stderr) output. The previous session's file is kept as `app.previous.log`.
private final class LogSink: Sendable {
    static let subsystem = Bundle.main.bundleIdentifier ?? "stremio-apple-tv"
    static let shared = LogSink()

    let fileURL: URL
    let minimumLevel: Log.Level
    private let queue = DispatchQueue(label: "log.sink", qos: .utility)
    private let handle: FileHandle?
    private let echoToStderr: Bool

    private init() {
        minimumLevel = LaunchOptions.current["STREMIO_LOG_LEVEL"].flatMap(Log.Level.init(name:)) ?? .debug
        #if DEBUG
        echoToStderr = true
        #else
        echoToStderr = false
        #endif

        let directory = Self.logDirectory()
        fileURL = directory.appending(path: "app.log")
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = directory.appending(path: "app.previous.log")
        try? fileManager.removeItem(at: previous)
        try? fileManager.moveItem(at: fileURL, to: previous)
        fileManager.createFile(atPath: fileURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: fileURL)
    }

    private static func logDirectory() -> URL {
        #if os(macOS)
        URL.libraryDirectory.appending(path: "Logs/\(subsystem)")
        #else
        URL.cachesDirectory.appending(path: "Logs")
        #endif
    }

    func append(level: Log.Level, category: String, message: String) {
        let timestamp = Date.now
        let thread = Thread.isMainThread ? "main" : "bg"
        queue.async { [handle, echoToStderr] in
            let line = "\(timestamp.formatted(.iso8601.time(includingFractionalSeconds: true))) \(level.label) [\(category)] (\(thread)) \(message)\n"
            let data = Data(line.utf8)
            handle?.write(data)
            if echoToStderr {
                FileHandle.standardError.write(data)
            }
        }
    }
}
