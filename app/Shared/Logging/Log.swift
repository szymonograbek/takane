import Foundation
import os
import Synchronization

/// App-wide logging. Every line goes to the unified log (subsystem = bundle id, one category
/// per `Log` instance) and to a plain-text file. In debug builds it is also echoed to stderr.
///
/// Usage: `Log.player.debug("loaded \(url)")`.
/// Read logs with `tail -f "<Log.fileURL>"` or Console.app filtered by subsystem.
/// Personal values the app holds are `Redacted`, so lines show codes for them in release builds.
/// Release builds also run every line through `RedactedMask`, which codes what personal values
/// it finds in text the app does not type, such as core's own logs.
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

    /// The lines written in `window` before `now`, across sessions, oldest first, under a header
    /// naming the app, its build and the window.
    static func export(_ window: LogWindow, at now: Date) -> String {
        LogSink.shared.export(window, at: now)
    }

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

    /// The install's key to release logs' codes, which the user may hand over. Nil in debug builds,
    /// whose logs show every value.
    static let key: LogKey? = {
        #if DEBUG
        nil
        #else
        LogKey.stored()
        #endif
    }()

    /// What `key` unlocks. Made with the first line, it derives its keys in the background, so only a
    /// line that codes a value in the first fraction of a second waits for them.
    static let secrets: LogSecrets? = key.map(LogSecrets.init)

    /// What lines show of `Redacted` and other personal values: revealed in debug builds, codes in
    /// release ones, each recorded in the session's legend as `RedactedMask.legendText(of:)` shows it.
    static let redaction: Redaction = {
        guard let codes = secrets?.pseudonymizer else { return .revealed }
        return .pseudonymized(Pseudonymizer { value in
            let code = codes.code(value)
            LogSink.shared.record(code, standingFor: RedactedMask.legendText(of: value))
            return code
        })
    }()

    /// The name of `value`'s enum case, `playing` for both `.playing` and `.playing(at: 3)`, or nil
    /// for a value that is not an enum.
    static func caseName(of value: Any) -> String? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .enum else { return nil }
        return mirror.children.first?.label ?? String(describing: value)
    }

    /// `value`'s description, cut to 200 characters so one line stays one line.
    static func summary(of value: Any) -> String {
        let text = String(describing: value)
        return text.count > 200 ? "\(text.prefix(200))…" : text
    }

    func write(_ level: Level, _ message: () -> String) {
        guard level >= LogSink.shared.minimumLevel else { return }
        let text = Redaction.$current.withValue(Self.redaction) { RedactedMask.line(message()) }
        switch level {
        case .trace, .debug: osLogger.debug("\(text, privacy: .public)")
        case .info: osLogger.info("\(text, privacy: .public)")
        case .warning: osLogger.warning("\(text, privacy: .public)")
        case .error: osLogger.error("\(text, privacy: .public)")
        }
        LogSink.shared.append(level: level, category: category, message: text)
    }
}

/// Serializes file (and stderr) output. The current session writes `app.log`, and in release builds
/// `app.legend`, the values its codes stand for, which never leave the device unsealed. At launch the
/// previous session's move to `sessions/<its start>.log` and `.legend`, and sessions that ended over
/// 7 days ago are deleted.
private final class LogSink: Sendable {
    static let subsystem = Bundle.main.bundleIdentifier ?? "stremio-apple-tv"
    static let shared = LogSink()

    let fileURL: URL
    private let legendURL: URL
    private let sessionsDirectory: URL
    let minimumLevel: Log.Level
    private let queue = DispatchQueue(label: "log.sink", qos: .utility)
    private let handle: FileHandle?
    private let legendHandle: FileHandle?
    /// Codes already in this session's legend.
    private let recorded = Mutex<Set<String>>([])
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
        legendURL = Self.legend(of: fileURL)
        sessionsDirectory = directory.appending(path: "sessions")
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        Self.archive(fileURL, into: sessionsDirectory)
        // Exports reach back as far as the longest window, so older sessions are of no use.
        let oldest = LogWindow.sevenDays.start(endingAt: .now)
        for session in Self.sessions(in: sessionsDirectory) where Self.lastWritten(session) < oldest {
            try? fileManager.removeItem(at: session)
            try? fileManager.removeItem(at: Self.legend(of: session))
        }
        fileManager.createFile(atPath: fileURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: fileURL)
        if Log.key == nil {
            legendHandle = nil
        } else {
            fileManager.createFile(atPath: legendURL.path, contents: nil)
            legendHandle = try? FileHandle(forWritingTo: legendURL)
        }
    }

    /// Where the values of `log`'s codes are.
    private static func legend(of log: URL) -> URL {
        log.deletingPathExtension().appendingPathExtension("legend")
    }

    /// Moves the previous session's log and legend into `directory`, named for when it started.
    private static func archive(_ file: URL, into directory: URL) {
        guard let started = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate else { return }
        let name = started.formatted(.iso8601.dateSeparator(.omitted).timeSeparator(.omitted))
        try? FileManager.default.moveItem(at: file, to: directory.appending(path: "\(name).log"))
        try? FileManager.default.moveItem(at: legend(of: file), to: directory.appending(path: "\(name).legend"))
    }

    /// Archived sessions, oldest first.
    private static func sessions(in directory: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func lastWritten(_ file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    func export(_ window: LogWindow, at now: Date) -> String {
        // Lines still queued belong in the export.
        queue.sync {}
        let start = window.start(endingAt: now)
        let files = Self.sessions(in: sessionsDirectory).filter { Self.lastWritten($0) >= start } + [fileURL]
        let lines = files.map { file in
            LogLines.written(since: start, in: Self.text(of: file))
        }
        let text = Self.header(window, start: start, end: now) + lines.joined()
        guard let secrets = Log.secrets else { return text }
        let legend = LogLegend.entries(in: files.map { Self.text(of: Self.legend(of: $0)) }, appearingIn: text)
        return text + LogLegend.section(secrets.seal(legend))
    }

    private static func text(of file: URL) -> String {
        (try? Data(contentsOf: file)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// Adds `code` to this session's legend, once.
    func record(_ code: String, standingFor value: String) {
        guard recorded.withLock({ $0.insert(code).inserted }) else { return }
        let line = LogLegend.line(code, standingFor: value)
        queue.async { [legendHandle] in legendHandle?.write(Data(line.utf8)) }
    }

    private static func header(_ window: LogWindow, start: Date, end: Date) -> String {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
        let build = switch Log.redaction {
        case .revealed: "Debug build"
        case .pseudonymized: "Release build, personal details replaced by codes"
        }
        return """
        Takane \(version), \(build)
        \(window.name): \(LogLines.timestamp(start)) to \(LogLines.timestamp(end))


        """
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
            let line = "\(LogLines.timestamp(timestamp)) \(level.label) [\(category)] (\(thread)) \(message)\n"
            let data = Data(line.utf8)
            handle?.write(data)
            if echoToStderr {
                FileHandle.standardError.write(data)
            }
        }
    }
}
