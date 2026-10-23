import Foundation

/// Reaches a WebDAV folder with Basic authentication in a header.
struct WebDAVClient: Sendable {
    let session: URLSession

    /// Checks that the folder answers WebDAV for these credentials: `PROPFIND` with `Depth: 0`,
    /// which a WebDAV server answers with a 207 multi-status.
    func check(_ endpoint: SourceEndpoint, _ username: SourceUsername, _ password: Password) async throws(SourceError) {
        var request = URLRequest(url: endpoint.url.rawValue)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.authorization(username, password), forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"<?xml version="1.0" encoding="utf-8"?><propfind xmlns="DAV:"><prop><resourcetype/></prop></propfind>"#.utf8)
        Log.network.debug("→ PROPFIND \(endpoint)")
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            Log.network.error("✕ \(endpoint): \(error)")
            throw .unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        Log.network.debug("← \(status) PROPFIND \(endpoint)")
        switch status {
        case 207: return
        case 401: throw .badCredentials
        default: throw .notWebDAV
        }
    }

    private static func authorization(_ username: SourceUsername, _ password: Password) -> String {
        "Basic \(Data("\(username.name.rawValue):\(password.rawValue)".utf8).base64EncodedString())"
    }
}
