import Foundation
import StremioBridge

enum CoreError: Error, CustomStringConvertible {
    /// The bridge rejected a call; the message comes from Rust.
    case bridge(String)
    case encoding(any Error)
    case decoding(field: CoreField, any Error)

    var description: String {
        switch self {
        case .bridge(let message): "bridge: \(message)"
        case .encoding(let error): "encoding: \(error)"
        case .decoding(let field, let error): "decoding \(field.rawValue): \(error)"
        }
    }
}

/// One of core's own events (`UserAuthenticated`, `AddonInstalled`, `Error`, …).
struct CoreEvent: Sendable {
    let name: String
    let args: JSONValue
}

/// The app's only handle on stremio-core. Thread-safe.
///
/// The bridge can be started once per process, so the app creates exactly one client.
final class CoreClient: Sendable {
    /// The model fields each `NewState` event names; read them with `state`.
    let changes: AsyncStream<[CoreField]>
    let events: AsyncStream<CoreEvent>
    private let host: CoreHost

    private init(host: CoreHost, changes: AsyncStream<[CoreField]>, events: AsyncStream<CoreEvent>) {
        self.host = host
        self.changes = changes
        self.events = events
    }

    /// Starts core and loads persisted state from `storageDirectory`. Blocks; call off the main thread.
    static func start(storageDirectory: URL) throws(CoreError) -> CoreClient {
        let (changes, continuation) = AsyncStream.makeStream(of: [CoreField].self, bufferingPolicy: .unbounded)
        let (events, eventContinuation) = AsyncStream.makeStream(of: CoreEvent.self, bufferingPolicy: .unbounded)
        let host = CoreHost(changes: continuation, events: eventContinuation)
        Log.core.info("starting bridge, storage at \(storageDirectory.path)")
        let started = ContinuousClock.now
        try callBridge { error in
            Data(storageDirectory.path.utf8).withSBBytes { directory in
                sb_initialize(host.makeCHost(), directory, error)
            }
        }
        Log.core.info("bridge started in \(ContinuousClock.now - started)")
        return CoreClient(host: host, changes: changes, events: events)
    }

    func dispatch(_ action: CoreAction, to field: CoreField? = nil) throws(CoreError) {
        let request: Data
        do {
            request = try JSONEncoder.core.encode(DispatchRequest(action: action, field: field))
        } catch {
            throw .encoding(error)
        }
        if action.isSensitive {
            Log.core.debug("dispatch → \(field?.rawValue ?? "null") <credentials redacted>")
        } else {
            Log.core.debug("dispatch → \(String(decoding: request, as: UTF8.self))")
        }
        try Self.callBridge { error in
            request.withSBBytes { sb_dispatch($0, error) }
        }
    }

    func state<State: Decodable>(_ field: CoreField, as type: State.Type = State.self) throws(CoreError) -> State {
        var state = SBOwnedBytes(ptr: nil, len: 0, cap: 0)
        try Self.callBridge { error in
            Data("\"\(field.rawValue)\"".utf8).withSBBytes { sb_get_state($0, &state, error) }
        }
        let json = Data(takingOwnershipOf: state)
        Log.core.trace("state \(field.rawValue): \(json.count) bytes")
        do {
            return try JSONDecoder().decode(State.self, from: json)
        } catch {
            Log.core.error("state \(field.rawValue) failed to decode: \(error)")
            throw .decoding(field: field, error)
        }
    }

    private static func callBridge(_ call: (UnsafeMutablePointer<SBOwnedBytes>) -> Bool) throws(CoreError) {
        var error = SBOwnedBytes(ptr: nil, len: 0, cap: 0)
        if call(&error) { return }
        throw .bridge(String(decoding: Data(takingOwnershipOf: error), as: UTF8.self))
    }
}

// MARK: - Host callbacks

/// Implements the `SBHost` callbacks Rust calls: logging, HTTP and runtime events.
private final class CoreHost: Sendable {
    private let changes: AsyncStream<[CoreField]>.Continuation
    private let events: AsyncStream<CoreEvent>.Continuation
    private let session: URLSession

    init(changes: AsyncStream<[CoreField]>.Continuation, events: AsyncStream<CoreEvent>.Continuation) {
        self.changes = changes
        self.events = events
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    /// The C view of this host. The bridge keeps it for the life of the process, so `self` is retained forever.
    func makeCHost() -> SBHost {
        SBHost(
            context: Unmanaged.passRetained(self).toOpaque(),
            log: { _, level, target, message in
                Log.rust(target: String(bytes: target)).write(Log.Level(level)) { String(bytes: message) }
            },
            fetch: { context, requestID, request in
                CoreHost.from(context)?.fetch(id: requestID, request: Data(bytes: request))
            },
            emit: { context, event in
                CoreHost.from(context)?.emit(Data(bytes: event))
            }
        )
    }

    private static func from(_ context: UnsafeMutableRawPointer?) -> CoreHost? {
        context.map { Unmanaged<CoreHost>.fromOpaque($0).takeUnretainedValue() }
    }

    private struct FetchRequest: Decodable {
        let method: String
        let url: String
        let headers: [String: String]
        let body: String?
    }

    private func fetch(id: UInt64, request json: Data) {
        let request: FetchRequest
        do {
            request = try JSONDecoder().decode(FetchRequest.self, from: json)
        } catch {
            Self.reject(id, "invalid fetch request: \(error)")
            return
        }
        guard let url = URL(string: request.url) else {
            Self.reject(id, "invalid URL: \(request.url)")
            return
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        if let body = request.body {
            urlRequest.httpBody = Data(body.utf8)
            if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        Log.network.debug("#\(id) → \(request.method) \(url.absoluteString) body=\(request.body?.count ?? 0)B")

        let session = session
        Task {
            let started = ContinuousClock.now
            do {
                let (data, response) = try await session.data(for: urlRequest)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let elapsed = ContinuousClock.now - started
                let level: Log.Level = (200..<300).contains(status) ? .debug : .warning
                Log.network.write(level) { "#\(id) ← \(status) \(data.count)B in \(elapsed) \(url.absoluteString)" }
                if level == .warning {
                    Log.network.warning("#\(id) body: \(String(decoding: data.prefix(500), as: UTF8.self))")
                }
                data.withSBBytes { sb_fetch_resolve(id, UInt16(clamping: status), $0) }
            } catch {
                Log.network.error("#\(id) ✕ \(url.absoluteString): \(error)")
                Self.reject(id, error.localizedDescription)
            }
        }
    }

    private static func reject(_ id: UInt64, _ message: String) {
        Log.network.error("#\(id) rejected: \(message)")
        Data(message.utf8).withSBBytes { sb_fetch_reject(id, $0) }
    }

    private struct RawEvent: Decodable {
        struct Core: Decodable {
            let event: String
            let args: JSONValue?
        }

        let name: String
        let fields: [CoreField]?
        let core: Core?

        private enum CodingKeys: String, CodingKey { case name, args }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            fields = name == "NewState" ? try container.decode([CoreField].self, forKey: .args) : nil
            core = name == "CoreEvent" ? try container.decode(Core.self, forKey: .args) : nil
        }
    }

    private func emit(_ json: Data) {
        do {
            let raw = try JSONDecoder().decode(RawEvent.self, from: json)
            if let fields = raw.fields {
                Log.core.debug("event NewState \(fields.map(\.rawValue))")
                changes.yield(fields)
            } else if let core = raw.core {
                // Auth events echo the request, password and token included.
                let payload = (core.args ?? .null).redacting(keys: ["password", "token", "authKey"])
                let level: Log.Level = core.event == "Error" ? .error : .info
                Log.core.write(level) { "event \(core.event) \(payload.compactDescription)" }
                events.yield(CoreEvent(name: core.event, args: payload))
            } else {
                Log.core.warning("unknown runtime event \(raw.name)")
            }
        } catch {
            // The raw JSON can hold credentials, so only its size is logged.
            Log.core.error("runtime event failed to decode (\(json.count) bytes): \(error)")
        }
    }
}

// MARK: - FFI helpers

private extension Log.Level {
    init(_ level: SBLogLevel) {
        switch level {
        case .error: self = .error
        case .warn: self = .warning
        case .info: self = .info
        case .debug: self = .debug
        case .trace: self = .trace
        }
    }
}

private extension Data {
    /// Copies borrowed bridge bytes.
    init(bytes: SBBytes) {
        if let pointer = bytes.ptr, bytes.len > 0 {
            self.init(bytes: pointer, count: bytes.len)
        } else {
            self.init()
        }
    }

    /// Copies bytes the bridge allocated, then frees them.
    init(takingOwnershipOf bytes: SBOwnedBytes) {
        guard let pointer = bytes.ptr else {
            self.init()
            return
        }
        self.init(bytes: pointer, count: bytes.len)
        sb_bytes_free(bytes)
    }

    func withSBBytes<Result>(_ body: (SBBytes) -> Result) -> Result {
        withUnsafeBytes { buffer in
            body(SBBytes(ptr: buffer.bindMemory(to: UInt8.self).baseAddress, len: buffer.count))
        }
    }
}

private extension String {
    init(bytes: SBBytes) {
        self.init(decoding: Data(bytes: bytes), as: UTF8.self)
    }
}

extension JSONEncoder {
    static var core: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }
}

private extension JSONValue {
    /// This value with the values under `keys` replaced, at any depth.
    func redacting(keys: Set<String>) -> JSONValue {
        switch self {
        case .object(let fields):
            .object(fields.reduce(into: [:]) { result, field in
                result[field.key] = keys.contains(field.key) ? .string("<redacted>") : field.value.redacting(keys: keys)
            })
        case .array(let values):
            .array(values.map { $0.redacting(keys: keys) })
        case .null, .bool, .number, .string:
            self
        }
    }
}

extension CoreAction {
    /// Carries a password or token, so logs show only its name.
    var isSensitive: Bool {
        if case .ctx(.authenticate) = self { true } else { false }
    }
}
