import Foundation
import Libmpv
import QuartzCore

/// What mpv reports back. Delivered on the main queue in the order mpv produced it.
enum MPVEvent: Sendable {
    case fileLoaded
    case endFile(reason: String, error: String?)
    case timePosition(Double)
    case duration(Double)
    case paused(Bool)
    case buffering(Bool)
    case videoSize(width: Int, height: Int)
    case hardwareDecoder(String)
}

/// One libmpv instance rendering into a `CAMetalLayer` through MoltenVK (`vo=gpu-next`).
///
/// libmpv's client API is thread-safe, so the handle is used from the caller's thread for
/// commands and from `MPVEventPump`'s queue for the event loop.
final class MPVEngine: @unchecked Sendable {
    let layer = MPVMetalLayer()

    private let handle: OpaquePointer
    private let pump: MPVEventPump

    fileprivate enum Property: String, CaseIterable {
        case timePosition = "time-pos"
        case duration = "duration"
        case pause = "pause"
        case pausedForCache = "paused-for-cache"
        case width = "width"
        case height = "height"
        case hardwareDecoder = "hwdec-current"

        var format: mpv_format {
            switch self {
            case .timePosition, .duration: MPV_FORMAT_DOUBLE
            case .pause, .pausedForCache: MPV_FORMAT_FLAG
            case .width, .height: MPV_FORMAT_INT64
            case .hardwareDecoder: MPV_FORMAT_STRING
            }
        }
    }

    enum StartError: Error { case createFailed, initializeFailed(String) }

    init(onEvent: @escaping @MainActor (MPVEvent) -> Void) throws {
        guard let handle = mpv_create() else { throw StartError.createFailed }
        self.handle = handle
        self.pump = MPVEventPump(handle: handle, onEvent: onEvent)

        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer.framebufferOnly = true

        let wid = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        var widValue = wid
        check(mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &widValue), "set wid")
        var options: [(String, String)] = [
            ("vo", "gpu-next"),
            ("gpu-api", "vulkan"),
            ("gpu-context", "moltenvk"),
            ("hwdec", "videotoolbox"),
            ("idle", "yes"),
            ("keep-open", "no"),
            ("input-default-bindings", "no"),
            ("network-timeout", "30"),
        ]
        #if os(macOS)
        // Only the macOS build of mpv has Lua, and so the youtube-dl hook this disables.
        options.append(("ytdl", "no"))
        #endif
        for (name, value) in options {
            check(mpv_set_option_string(handle, name, value), "option \(name)=\(value)")
        }
        check(mpv_request_log_messages(handle, "v"), "request log messages")

        let status = mpv_initialize(handle)
        guard status >= 0 else {
            // deinit destroys the handle.
            throw StartError.initializeFailed(String(cString: mpv_error_string(status)))
        }
        for property in Property.allCases {
            mpv_observe_property(handle, 0, property.rawValue, property.format)
        }
        // Unretained: deinit clears the callback (which waits out a running one) before `pump` is released.
        mpv_set_wakeup_callback(handle, { context in
            guard let context else { return }
            Unmanaged<MPVEventPump>.fromOpaque(context).takeUnretainedValue().drain()
        }, Unmanaged.passUnretained(pump).toOpaque())
        Log.player.info("mpv initialized (\(String(cString: mpv_client_name(handle))), api \(mpv_client_api_version()))")
    }

    deinit {
        mpv_set_wakeup_callback(handle, nil, nil)
        pump.waitUntilIdle()
        mpv_terminate_destroy(handle)
        Log.player.info("mpv destroyed")
    }

    /// Starts playing `url`. `headers` are sent with every HTTP request mpv makes for it.
    func load(_ url: URL, headers: [String: String]) {
        // `append` adds one list item verbatim; setting the whole property would split values on commas.
        command("change-list", "http-header-fields", "clr", "")
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            command("change-list", "http-header-fields", "append", "\(name): \(value)")
        }
        Log.player.info("loadfile \(url.absoluteString) headers=\(headers.keys.sorted())")
        command("loadfile", url.absoluteString, "replace")
    }

    func setPaused(_ paused: Bool) {
        var flag: Int32 = paused ? 1 : 0
        check(mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &flag), "set pause=\(paused)")
    }

    func seek(by seconds: Double) {
        command("seek", String(seconds), "relative")
    }

    func stop() {
        command("stop")
    }

    /// Reads any mpv property as text (e.g. `osd-width`, `frame-drop-count`), for diagnostics.
    func property(_ name: String) -> String? {
        guard let value = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(value) }
        return String(cString: value)
    }

    /// The current video frame at its native size, without subtitles or UI.
    /// Nil in simulators: MoltenVK's texture readback crashes the simulator's Metal driver
    /// (`MTLSimDevice newBufferWithLength` → `_xpc_api_misuse`).
    func snapshot() -> CGImage? {
        #if targetEnvironment(simulator)
        Log.player.warning("snapshot is unavailable in the simulator")
        return nil
        #else
        var result = mpv_node()
        let status = withCArguments(["screenshot-raw", "video"]) { mpv_command_ret(handle, $0, &result) }
        defer { mpv_free_node_contents(&result) }
        guard status >= 0 else {
            check(status, "screenshot-raw")
            return nil
        }
        guard result.format == MPV_FORMAT_NODE_MAP, let map = result.u.list?.pointee else { return nil }

        var width = 0, height = 0, stride = 0
        var format = ""
        var pixels: Data?
        for index in 0..<Int(map.num) {
            guard let key = map.keys?[index], let value = map.values?[index] else { continue }
            switch String(cString: key) {
            case "w": width = Int(value.u.int64)
            case "h": height = Int(value.u.int64)
            case "stride": stride = Int(value.u.int64)
            case "format": format = value.u.string.map { String(cString: $0) } ?? ""
            case "data":
                if let bytes = value.u.ba?.pointee, let data = bytes.data {
                    pixels = Data(bytes: data, count: bytes.size)
                }
            default: break
            }
        }
        // mpv documents "bgr0" as the default raw screenshot format.
        guard format == "bgr0", width > 0, height > 0, let pixels, let provider = CGDataProvider(data: pixels as CFData) else {
            Log.player.error("unexpected raw screenshot: \(format) \(width)x\(height)")
            return nil
        }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
        #endif
    }

    private func command(_ arguments: String...) {
        Log.player.debug("command \(arguments.joined(separator: " "))")
        check(withCArguments(arguments) { mpv_command(handle, $0) }, "command \(arguments.first ?? "")")
    }

    /// Calls `body` with a NULL-terminated C argv for an mpv command.
    private func withCArguments<Result>(
        _ arguments: [String],
        _ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>) -> Result
    ) -> Result {
        let cStrings = arguments.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        var argv: [UnsafePointer<CChar>?] = cStrings.map { $0.map { UnsafePointer($0) } }
        argv.append(nil)
        return argv.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { fatalError("argv always holds the NULL terminator") }
            return body(base)
        }
    }

    private func check(_ status: Int32, _ what: @autoclosure () -> String) {
        if status < 0 {
            Log.player.error("\(what()) failed: \(String(cString: mpv_error_string(status)))")
        }
    }
}

/// Runs mpv's event loop on its own queue and forwards events to the main actor.
/// Holds no reference to `MPVEngine`, so the engine is never released from this queue.
private final class MPVEventPump: @unchecked Sendable {
    private let handle: OpaquePointer
    private let queue = DispatchQueue(label: "mpv.events", qos: .userInitiated)
    private let onEvent: @MainActor (MPVEvent) -> Void

    init(handle: OpaquePointer, onEvent: @escaping @MainActor (MPVEvent) -> Void) {
        self.handle = handle
        self.onEvent = onEvent
    }

    func drain() {
        queue.async { [self] in
            while let event = mpv_wait_event(handle, 0)?.pointee, event.event_id != MPV_EVENT_NONE {
                if let translated = translate(event) {
                    let onEvent = onEvent
                    DispatchQueue.main.async { MainActor.assumeIsolated { onEvent(translated) } }
                }
            }
        }
    }

    func waitUntilIdle() {
        queue.sync {}
    }

    private func translate(_ event: mpv_event) -> MPVEvent? {
        switch event.event_id {
        case MPV_EVENT_LOG_MESSAGE:
            guard let message = event.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee else { return nil }
            let prefix = String(cString: message.prefix)
            let text = String(cString: message.text).trimmingCharacters(in: .newlines)
            let level: Log.Level = switch message.log_level {
            case MPV_LOG_LEVEL_FATAL, MPV_LOG_LEVEL_ERROR: .error
            case MPV_LOG_LEVEL_WARN: .warning
            case MPV_LOG_LEVEL_INFO: .info
            default: .debug
            }
            Log.player.write(level) { "mpv[\(prefix)] \(text)" }
            return nil
        case MPV_EVENT_FILE_LOADED:
            Log.player.info("file loaded")
            return .fileLoaded
        case MPV_EVENT_END_FILE:
            guard let endFile = event.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee else { return nil }
            let reason = switch endFile.reason {
            case MPV_END_FILE_REASON_EOF: "eof"
            case MPV_END_FILE_REASON_STOP: "stop"
            case MPV_END_FILE_REASON_QUIT: "quit"
            case MPV_END_FILE_REASON_ERROR: "error"
            case MPV_END_FILE_REASON_REDIRECT: "redirect"
            default: "unknown"
            }
            let error = endFile.error < 0 ? String(cString: mpv_error_string(endFile.error)) : nil
            Log.player.write(error == nil ? .info : .error) { "end file: \(reason) \(error ?? "")" }
            return .endFile(reason: reason, error: error)
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let change = event.data?.assumingMemoryBound(to: mpv_event_property.self).pointee,
                  let property = MPVEngine.Property(rawValue: String(cString: change.name)),
                  change.format != MPV_FORMAT_NONE,
                  let data = change.data
            else { return nil }
            let translated: MPVEvent = switch property {
            case .timePosition: .timePosition(data.load(as: Double.self))
            case .duration: .duration(data.load(as: Double.self))
            case .pause: .paused(data.load(as: Int32.self) != 0)
            case .pausedForCache: .buffering(data.load(as: Int32.self) != 0)
            case .width, .height: videoSizeEvent()
            case .hardwareDecoder: .hardwareDecoder(String(cString: data.load(as: UnsafePointer<CChar>.self)))
            }
            if case .timePosition = translated {} else {
                Log.player.debug("property \(property.rawValue) → \(translated)")
            }
            return translated
        case MPV_EVENT_SHUTDOWN:
            Log.player.info("mpv shutdown")
            return nil
        default:
            Log.player.trace("event \(String(cString: mpv_event_name(event.event_id)))")
            return nil
        }
    }

    private func videoSizeEvent() -> MPVEvent {
        var width: Int64 = 0
        var height: Int64 = 0
        mpv_get_property(handle, "width", MPV_FORMAT_INT64, &width)
        mpv_get_property(handle, "height", MPV_FORMAT_INT64, &height)
        return .videoSize(width: Int(width), height: Int(height))
    }
}

/// Works around MoltenVK shrinking the drawable to 1×1 while presenting, which causes flicker
/// (https://github.com/mpv-player/mpv/pull/13651).
final class MPVMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if newValue.width > 1, newValue.height > 1 {
                super.drawableSize = newValue
            }
        }
    }
}
