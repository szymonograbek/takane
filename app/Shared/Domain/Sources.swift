import Foundation

/// Names one of the user's sources: eight lowercase letters and digits, made when it is added. Safe
/// inside an add-on id and a host name, since it holds no `:`, `.` or whitespace.
struct SourceID: Hashable, Sendable, CustomStringConvertible {
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")

    let rawValue: String

    init?(_ text: String) {
        guard text.count == 8, text.allSatisfy(Self.alphabet.contains) else { return nil }
        rawValue = text
    }

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    static func random() -> SourceID {
        SourceID(rawValue: String((0..<8).compactMap { _ in alphabet.randomElement() }))
    }

    var description: String { rawValue }
}

enum SourceKind: Hashable, Sendable {
    case jellyfin
    case webDAV
}

/// Where a source's server is: an http or https URL with a host. It refuses a URL holding a user,
/// a password or a query, so a pasted link cannot carry a credential into a source's settings.
struct SourceEndpoint: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// Names the user's server, which release logs keep private.
    let url: Redacted<URL>

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              components.host?.isEmpty == false,
              components.user == nil, components.password == nil, components.query == nil,
              let url = components.url
        else { return nil }
        self.url = Redacted(url)
    }

    var description: String { url.description }
    var debugDescription: String { description }
}

/// A non-empty user name on a source's server, as typed but trimmed.
struct SourceUsername: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let name: Redacted<String>

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        name = Redacted(trimmed)
    }

    var description: String { name.description }
    var debugDescription: String { description }
}

/// What signs in to a source's server.
struct SourceLogin: Equatable, Sendable {
    let endpoint: SourceEndpoint
    let username: SourceUsername
    let password: Password
}

/// What editing a source does to its password.
enum PasswordChange: Equatable, Sendable {
    /// Signs in with what is stored.
    case keep
    case replace(Password)
}

/// A media server the user added. It holds no secret, so it can be state, listed and logged.
struct MediaSource: Identifiable, Equatable, Sendable {
    let id: SourceID
    let kind: SourceKind
    /// The server's name, or the folder's for WebDAV.
    let name: Redacted<String>
    let endpoint: SourceEndpoint
    let username: SourceUsername
}

enum SourceError: Error, Equatable, Sendable {
    /// The server did not answer.
    case unreachable
    case badCredentials
    /// The server answered, but not as a Jellyfin server would.
    case notJellyfin
    /// The server answered, but not as a WebDAV folder would.
    case notWebDAV
    /// The server answered something this app cannot read.
    case invalidResponse(reason: String)
    /// The source was removed.
    case notFound
    /// This device could not keep the source's sign-in.
    case storageFailed(reason: String)
}

/// The user's own media servers. They stay on this device, apart from the account.
protocol MediaSourceService: Sendable {
    /// The sources now, in the order they were added, then after every change.
    func sources() -> AsyncStream<[MediaSource]>

    /// Signs in, then keeps the source. Nothing is kept when signing in fails.
    func add(_ kind: SourceKind, _ login: SourceLogin) async throws(SourceError) -> MediaSource

    /// Signs in with the new settings, then replaces the source's. The old ones stay when signing in fails.
    func update(
        _ id: SourceID, endpoint: SourceEndpoint, username: SourceUsername, password: PasswordChange
    ) async throws(SourceError) -> MediaSource

    /// Removing a source that is not there succeeds.
    func remove(_ id: SourceID) async throws(SourceError)
}
