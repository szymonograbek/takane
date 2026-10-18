import Foundation

/// Why an HTTP JSON request produced no value. Adapters translate it into their port's error.
enum HTTPFailure: Error, Equatable, Sendable {
    case transport(String)
    /// A response outside 2xx.
    case status(Int)
    case decoding(String)
}

extension URLSession {
    /// Performs `request` and decodes a 2xx body as `Value`. Logs the URL, never the headers,
    /// so credentials belong in headers.
    func json<Value: Decodable>(
        _ type: Value.Type,
        for request: URLRequest,
        decoder: JSONDecoder
    ) async throws(HTTPFailure) -> Value {
        let url = request.url?.absoluteString ?? "?"
        Log.network.debug("→ \(request.httpMethod ?? "GET") \(url)")
        let started = ContinuousClock.now
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.data(for: request)
        } catch {
            Log.network.error("✕ \(url): \(error)")
            throw .transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let elapsed = ContinuousClock.now - started
        guard (200..<300).contains(status) else {
            Log.network.warning("← \(status) \(data.count)B in \(elapsed) \(url): \(String(decoding: data.prefix(500), as: UTF8.self))")
            throw .status(status)
        }
        Log.network.debug("← \(status) \(data.count)B in \(elapsed) \(url)")
        do {
            return try decoder.decode(type, from: data)
        } catch {
            Log.network.error("undecodable \(Value.self) from \(url): \(error)")
            throw .decoding(String(describing: error))
        }
    }
}
