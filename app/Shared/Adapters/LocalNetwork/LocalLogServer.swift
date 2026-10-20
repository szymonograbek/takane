import Foundation
import Network
import os

/// Shares the logs over plain HTTP on the local network, at an address short enough to type on a
/// phone: `http://192.168.1.20:8080/k7fm`. Only `GET /<token>` answers, with the logs of the
/// window shared at the time of the request as a download; anything else is a 404.
actor LocalLogServer: LogSharing {
    private struct Serving: Sendable {
        let listener: NWListener
        let link: LogLink
    }

    /// The listener being started or serving. Joined by every `share` until `stop`.
    private var serving: Task<Result<Serving, LogSharingError>, Never>?
    /// Read by each request, on the listener's queue.
    private let sharedWindow = OSAllocatedUnfairLock(initialState: LogWindow.default)
    private let queue = DispatchQueue(label: "log.server")

    private static let preferredPort: NWEndpoint.Port = 8080
    /// No 0, o, 1, l or i, so the token reads back unambiguously.
    private static let tokenAlphabet = Array("23456789abcdefghjkmnpqrstuvwxyz")

    func share(_ window: LogWindow) async throws(LogSharingError) -> LogLink {
        sharedWindow.withLock { $0 = window }
        let task = serving ?? Task { [sharedWindow, queue] in await Self.start(window: sharedWindow, queue: queue) }
        serving = task
        switch await task.value {
        case .success(let serving):
            return serving.link
        case .failure(let error):
            if self.serving == task { self.serving = nil }
            throw error
        }
    }

    func stop() async {
        guard let task = serving else { return }
        serving = nil
        if case .success(let serving) = await task.value {
            serving.listener.cancel()
            Log.network.info("log server stopped")
        }
    }

    private static func start(window: OSAllocatedUnfairLock<LogWindow>, queue: DispatchQueue) async -> Result<Serving, LogSharingError> {
        guard let address = localAddress() else { return .failure(.noLocalNetwork) }
        let token = String((0..<4).compactMap { _ in tokenAlphabet.randomElement() })
        let accept: @Sendable (NWConnection) -> Void = { connection in
            answer(connection, token: token, window: window, queue: queue)
        }
        let listening = switch await listen(on: preferredPort, queue: queue, accept: accept) {
        case .success(let listener): Result<NWListener, LogSharingError>.success(listener)
        // Something else has the port; any free one will do.
        case .failure: await listen(on: .any, queue: queue, accept: accept)
        }
        return listening.flatMap { listener in
            guard let port = listener.port else { return .failure(.listenerFailed(reason: "no port")) }
            guard let url = URL(string: "http://\(address):\(port.rawValue)/\(token)") else {
                return .failure(.listenerFailed(reason: "no URL for \(address)"))
            }
            let link = LogLink(url: Redacted(url))
            Log.network.info("log server sharing at \(link.url)")
            return .success(Serving(listener: listener, link: link))
        }
    }

    /// A listener on `port` once it is ready, handing each connection to `accept`.
    private static func listen(
        on port: NWEndpoint.Port, queue: DispatchQueue, accept: @escaping @Sendable (NWConnection) -> Void
    ) async -> Result<NWListener, LogSharingError> {
        let parameters = NWParameters.tcp
        // A port the last share just closed is still reserved for a while.
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: port)
        } catch {
            return .failure(.listenerFailed(reason: "\(error)"))
        }
        // Starting without it fails with EINVAL.
        listener.newConnectionHandler = accept
        let resumed = OSAllocatedUnfairLock(initialState: false)
        let ready = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, LogSharingError>, Never>) in
            listener.stateUpdateHandler = { state in
                let outcome: Result<Void, LogSharingError>? = switch state {
                case .ready: .success(())
                case .failed(let error), .waiting(let error): .failure(.listenerFailed(reason: "\(error)"))
                case .cancelled: .failure(.listenerFailed(reason: "cancelled"))
                case .setup: nil
                @unknown default: nil
                }
                guard let outcome else { return }
                let first = resumed.withLock { wasResumed in
                    defer { wasResumed = true }
                    return !wasResumed
                }
                if first {
                    continuation.resume(returning: outcome)
                } else if case .failed(let error) = state {
                    Log.network.warning("log server failed: \(error)")
                }
            }
            listener.start(queue: queue)
        }
        if case .failure = ready { listener.cancel() }
        return ready.map { listener }
    }

    private static func answer(
        _ connection: NWConnection, token: String, window: OSAllocatedUnfairLock<LogWindow>, queue: DispatchQueue
    ) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { request, _, _, _ in
            let response = if requestedPath(request ?? Data()) == "/\(token)" {
                logs(window.withLock { $0 })
            } else {
                notFound
            }
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// The path of a `GET` request, from its request line `GET /path HTTP/1.1`.
    private static func requestedPath(_ request: Data) -> Substring? {
        let requestLine = String(decoding: request, as: UTF8.self).prefix { !$0.isNewline }
        let parts = requestLine.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET" else { return nil }
        return parts[1]
    }

    private static func logs(_ window: LogWindow) -> Data {
        let now = Date.now
        let body = Data(Log.export(window, at: now).utf8)
        let fileTime = DateFormatter()
        fileTime.locale = Locale(identifier: "en_US_POSIX")
        fileTime.dateFormat = "yyyyMMdd-HHmm"
        Log.network.info("log server sent \(window.name), \(body.count)B")
        return response(status: "200 OK", headers: [
            "Content-Type": "text/plain; charset=utf-8",
            "Content-Disposition": "attachment; filename=\"takane-logs-\(fileTime.string(from: now)).log\"",
        ], body: body)
    }

    private static let notFound = response(status: "404 Not Found", headers: ["Content-Type": "text/plain; charset=utf-8"], body: Data("Not found\n".utf8))

    private static func response(status: String, headers: [String: String], body: Data) -> Data {
        let fields = headers.merging(["Content-Length": "\(body.count)", "Connection": "close"]) { field, _ in field }
        let head = (["HTTP/1.1 \(status)"] + fields.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }).joined(separator: "\r\n")
        return Data("\(head)\r\n\r\n".utf8) + body
    }

    /// This device's IPv4 address on the local network: Wi-Fi or Ethernet (`en0`) when it has one.
    private static func localAddress() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }
        var addresses: [(interface: String, address: String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
                continue
            }
            let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            addresses.append((String(cString: interface.ifa_name), text))
        }
        return (addresses.first { $0.interface == "en0" } ?? addresses.first)?.address
    }
}
