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

/// What the user calls a source: a non-empty name, as typed but trimmed.
struct SourceName: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let text: Redacted<String>

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.text = Redacted(trimmed)
    }

    /// The server's host, for a source whose server gives no name.
    init(hostOf endpoint: SourceEndpoint) {
        text = Redacted(endpoint.url.rawValue.host() ?? endpoint.description)
    }

    var description: String { text.description }
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

/// What editing a source sets.
struct SourceEdit: Equatable, Sendable {
    let name: SourceName
    let endpoint: SourceEndpoint
    let username: SourceUsername
    let password: PasswordChange
}

/// A media server the user added. It holds no secret, so it can be state, listed and logged.
struct MediaSource: Identifiable, Equatable, Sendable {
    let id: SourceID
    let kind: SourceKind
    /// The server's name, or the folder's for WebDAV, until the user renames it.
    let name: SourceName
    let endpoint: SourceEndpoint
    let username: SourceUsername
    /// The kinds the user chose for a WebDAV source's top-level folders. A folder missing here takes
    /// the kind its videos suggest. Jellyfin's libraries have their kinds on the server.
    var folderKinds: [LibraryFolder: FolderKind] = [:]
}

/// One of a WebDAV source's top-level folders, each a library: its name under the source's folder,
/// so editing the folder's address keeps it.
struct LibraryFolder: Hashable, Sendable, CustomStringConvertible {
    let name: Redacted<String>

    /// Nil for a name that is no folder's, empty or holding a `/`.
    init?(_ name: String) {
        guard !name.isEmpty, !name.contains("/") else { return nil }
        self.name = Redacted(name)
    }

    var description: String { name.description }
}

/// What a library folder holds, which decides its catalog's type and whether its titles are looked
/// up by name: only films in Movies and shows in Shows are, so a home video called like a film
/// keeps its own name and details.
enum FolderKind: Hashable, Sendable, CaseIterable {
    case movies
    case shows
    case otherVideos
}

/// A library folder and the kind its videos suggest, which it has until the user picks one.
struct FolderSuggestion: Hashable, Sendable {
    let folder: LibraryFolder
    let kind: FolderKind
}

/// A folder on a source, named as only the source's adapter reads it: a Jellyfin library or folder,
/// or a folder's path under a WebDAV folder.
struct SourceFolderID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Redacted, since a path's key can be checked against guessed folder names.
    var description: String { Redacted(rawValue).description }
}

/// What a source's folder holds, as browsing shows it.
enum SourceEntry: Hashable, Sendable {
    case folder(SourceFolderID, name: Redacted<String>)
    /// A movie, show or video, known by its IMDb id when the source knows it, else by the source's own id.
    case title(MetaPreview)
    /// A file of one of a show's episodes.
    case episode(show: MetaPreview, season: Int, episode: Int, name: Redacted<String>)
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
    /// The folder is no longer on the server.
    case folderGone
    /// This device could not keep the source's sign-in.
    case storageFailed(reason: String)
}

/// The user's own media servers. They stay on this device, apart from the account.
protocol MediaSourceService: Sendable {
    /// The sources now, in the order they were added, then after every change.
    func sources() -> AsyncStream<[MediaSource]>

    /// Signs in, then keeps the source. Nothing is kept when signing in fails.
    func add(_ kind: SourceKind, _ login: SourceLogin) async throws(SourceError) -> MediaSource

    /// Signs in with the new settings, then replaces the source's, its name included. The old ones
    /// stay when signing in fails.
    func update(_ id: SourceID, _ edit: SourceEdit) async throws(SourceError) -> MediaSource

    /// Removing a source that is not there succeeds.
    func remove(_ id: SourceID) async throws(SourceError)

    /// What a folder of the source holds: its folders, then its titles and episode files. Nil is the
    /// source's root: a Jellyfin server's libraries, or the top of a WebDAV folder.
    func browse(_ id: SourceID, folder: SourceFolderID?) async throws(SourceError) -> [SourceEntry]

    /// A WebDAV source's library folders, by name, with the kind each one's videos suggest. Empty for
    /// a Jellyfin server.
    func libraryFolders(_ id: SourceID) async throws(SourceError) -> [FolderSuggestion]

    /// Keeps the user's kind for a WebDAV source's library folder, then lists the source again with it.
    func setKind(_ kind: FolderKind, of folder: LibraryFolder, on id: SourceID) async throws(SourceError)
}
