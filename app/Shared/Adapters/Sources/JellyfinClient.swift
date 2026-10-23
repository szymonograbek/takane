import Foundation

/// Signs in to a Jellyfin server. Every request names the app and this device's sign-in in the
/// `Authorization: MediaBrowser …` header, the token too once signed in, never in the URL.
struct JellyfinClient: Sendable {
    let session: URLSession
    /// The app's version, which the server shows beside this device's sign-in.
    let version: String

    /// Checks that the server is Jellyfin, then trades the password for a token. Each source signs
    /// in as its own device, `takane-<id>`, since signing in again on a device ends its earlier sign-in.
    func signIn(_ login: SourceLogin, for id: SourceID) async throws(SourceError) -> (serverName: String, session: JellyfinSession) {
        let info = try await publicInfo(login.endpoint)
        var request = URLRequest(url: login.endpoint.url.rawValue.appending(path: "Users/AuthenticateByName"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorization(for: id, token: nil), forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(Credentials(username: login.username.name.rawValue, password: login.password.rawValue))
        let answer = try await signedIn(request, Authentication.self)
        return (info.serverName, JellyfinSession(userID: answer.user.id, token: answer.accessToken))
    }

    /// Checks that the server is Jellyfin and that `session` still signs in `username`.
    func check(_ session: JellyfinSession, at endpoint: SourceEndpoint, as username: SourceUsername, for id: SourceID) async throws(SourceError) -> String {
        let info = try await publicInfo(endpoint)
        var request = URLRequest(url: endpoint.url.rawValue.appending(path: "Users/Me"))
        request.setValue(authorization(for: id, token: session.token), forHTTPHeaderField: "Authorization")
        let user = try await signedIn(request, User.self)
        guard user.name.caseInsensitiveCompare(username.name.rawValue) == .orderedSame else { throw .badCredentials }
        return info.serverName
    }

    /// The server's public information, which any Jellyfin server gives without signing in.
    private func publicInfo(_ endpoint: SourceEndpoint) async throws(SourceError) -> PublicInfo {
        let request = URLRequest(url: endpoint.url.rawValue.appending(path: "System/Info/Public"))
        do {
            return try await session.json(PublicInfo.self, for: request, decoder: JSONDecoder())
        } catch {
            switch error {
            case .transport: throw .unreachable
            case .status, .decoding: throw .notJellyfin
            }
        }
    }

    private func signedIn<Value: Decodable>(_ request: URLRequest, _ type: Value.Type) async throws(SourceError) -> Value {
        do {
            return try await session.json(type, for: request, decoder: JSONDecoder())
        } catch {
            switch error {
            case .transport: throw .unreachable
            case .status(401): throw .badCredentials
            case .status(let status): throw .invalidResponse(reason: "status \(status)")
            case .decoding(let reason): throw .invalidResponse(reason: reason)
            }
        }
    }

    private func authorization(for id: SourceID, token: String?) -> String {
        #if os(tvOS)
        let device = "Apple TV"
        #else
        let device = "Mac"
        #endif
        let fields = #"Client="Takane", Device="\#(device)", DeviceId="takane-\#(id.rawValue)", Version="\#(version)""#
        return token.map { #"MediaBrowser \#(fields), Token="\#($0)""# } ?? "MediaBrowser \(fields)"
    }

    /// Decoding `id` and `version` too is what tells a Jellyfin server from another that answers the path.
    private struct PublicInfo: Decodable {
        let serverName: String
        let id: String
        let version: String

        private enum CodingKeys: String, CodingKey {
            case serverName = "ServerName", id = "Id", version = "Version"
        }
    }

    private struct Credentials: Encodable {
        let username: String
        let password: String

        private enum CodingKeys: String, CodingKey {
            case username = "Username", password = "Pw"
        }
    }

    private struct Authentication: Decodable {
        let user: User
        let accessToken: String

        private enum CodingKeys: String, CodingKey {
            case user = "User", accessToken = "AccessToken"
        }
    }

    private struct User: Decodable {
        let id: String
        let name: String

        private enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name"
        }
    }
}
