import Foundation
import Security

/// What signs in to a source's server, kept beside the source.
enum SourceCredential: Equatable, Sendable {
    /// Never the password: Jellyfin trades it for a token at sign-in.
    case jellyfin(JellyfinSession)
    /// WebDAV's Basic authentication sends the password itself.
    case webDAV(Password)
}

/// This device's sign-in on a Jellyfin server. Its descriptions hide the token.
struct JellyfinSession: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let userID: String
    let token: String

    var description: String { "JellyfinSession(<token>)" }
    var debugDescription: String { description }
}

/// Keeps the sources in the Keychain, on this device only and readable once it has been unlocked
/// since starting. One generic password item per source, its account the `SourceID`: the item's
/// `kSecAttrGeneric` holds what the source shows, as JSON, and its data the credential, so listing
/// the sources reads no secret and removing one is one delete.
///
/// It uses the data protection keychain on macOS too, which never asks for the login keychain's
/// password, even for an ad hoc signed build whose signature changes with every build.
struct KeychainSourceStore: Sendable {
    /// Every item of the store has it, such as `com.ograbek.takane.sources`.
    let service: String

    /// The stored sources, oldest first.
    func sources() throws(SourceError) -> [MediaSource] {
        var query = items
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let found = result as? [[String: Any]] else { throw Self.failure(status, "listing sources") }
        let oldestFirst = found.sorted { Self.created($0) < Self.created($1) }
        return oldestFirst.compactMap { attributes in
            guard let source = Self.source(from: attributes) else {
                Log.sources.warning("a stored source could not be read")
                return nil
            }
            return source
        }
    }

    func credential(for id: SourceID) throws(SourceError) -> SourceCredential {
        var query = item(id)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw .notFound }
        guard status == errSecSuccess, let data = result as? Data else { throw Self.failure(status, "reading a sign-in") }
        guard let credential = (try? JSONDecoder().decode(StoredSecret.self, from: data))?.credential else {
            throw .storageFailed(reason: "a stored sign-in could not be read")
        }
        return credential
    }

    /// Adds the source, or replaces the one with its id. `source.kind` must be the credential's.
    func save(_ source: MediaSource, _ credential: SourceCredential) throws(SourceError) {
        let listing: Data
        let secret: Data
        do {
            listing = try JSONEncoder().encode(StoredListing(source))
            secret = try JSONEncoder().encode(StoredSecret(credential))
        } catch {
            throw .storageFailed(reason: "encoding: \(error)")
        }
        let contents: [String: Any] = [kSecAttrGeneric as String: listing, kSecValueData as String: secret]
        var added = item(source.id).merging(contents) { _, new in new }
        added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        added[kSecAttrSynchronizable as String] = false
        var status = SecItemAdd(added as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(item(source.id) as CFDictionary, contents as CFDictionary)
        }
        guard status == errSecSuccess else { throw Self.failure(status, "saving a source") }
    }

    /// Removing a source that is not stored succeeds.
    func remove(_ id: SourceID) throws(SourceError) {
        let status = SecItemDelete(item(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.failure(status, "removing a source") }
    }

    private var items: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func item(_ id: SourceID) -> [String: Any] {
        items.merging([kSecAttrAccount as String: id.rawValue]) { _, new in new }
    }

    private static func created(_ attributes: [String: Any]) -> Date {
        attributes[kSecAttrCreationDate as String] as? Date ?? .distantPast
    }

    private static func source(from attributes: [String: Any]) -> MediaSource? {
        guard let account = attributes[kSecAttrAccount as String] as? String, let id = SourceID(account),
              let data = attributes[kSecAttrGeneric as String] as? Data,
              let listing = try? JSONDecoder().decode(StoredListing.self, from: data),
              let name = SourceName(listing.name), let endpoint = SourceEndpoint(listing.endpoint.absoluteString),
              let username = SourceUsername(listing.username)
        else { return nil }
        return MediaSource(id: id, kind: listing.kind.kind, name: name, endpoint: endpoint, username: username)
    }

    private static func failure(_ status: OSStatus, _ action: String) -> SourceError {
        .storageFailed(reason: "\(action): Keychain status \(status)")
    }
}

/// What a source shows, as the item's `kSecAttrGeneric` holds it.
private struct StoredListing: Codable {
    enum Kind: String, Codable {
        case jellyfin, webDAV

        var kind: SourceKind {
            switch self {
            case .jellyfin: .jellyfin
            case .webDAV: .webDAV
            }
        }
    }

    let kind: Kind
    let name: String
    let endpoint: URL
    let username: String

    init(_ source: MediaSource) {
        kind = switch source.kind {
        case .jellyfin: .jellyfin
        case .webDAV: .webDAV
        }
        name = source.name.text.rawValue
        endpoint = source.endpoint.url.rawValue
        username = source.username.name.rawValue
    }
}

/// A credential as the item's data holds it.
private enum StoredSecret: Codable {
    case jellyfin(userID: String, token: String)
    case webDAV(password: String)

    init(_ credential: SourceCredential) {
        self = switch credential {
        case .jellyfin(let session): .jellyfin(userID: session.userID, token: session.token)
        case .webDAV(let password): .webDAV(password: password.rawValue)
        }
    }

    var credential: SourceCredential? {
        switch self {
        case .jellyfin(let userID, let token): .jellyfin(JellyfinSession(userID: userID, token: token))
        case .webDAV(let password): Password(password).map(SourceCredential.webDAV)
        }
    }
}
