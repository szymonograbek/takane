import Foundation
import Synchronization

/// The user's media sources: signed in to when added or edited, kept in the Keychain, and listed in
/// core as in-process add-ons, one per source. For now each answers its manifest only.
final class SourceLibrary: MediaSourceService, CoreInProcessAddons, CorePlaybackLinks {
    private struct State {
        var sources: [MediaSource]
        var observers: [UUID: AsyncStream<[MediaSource]>.Continuation] = [:]
    }

    private let store: KeychainSourceStore
    private let jellyfin: JellyfinClient
    private let webDAV: WebDAVClient
    private let state: Mutex<State>

    /// Reads the stored sources.
    init(store: KeychainSourceStore, jellyfin: JellyfinClient, webDAV: WebDAVClient) {
        self.store = store
        self.jellyfin = jellyfin
        self.webDAV = webDAV
        let stored: [MediaSource]
        do {
            stored = try store.sources()
        } catch {
            Log.sources.error("reading the sources failed: \(error)")
            stored = []
        }
        Log.sources.info("\(stored.count) sources stored")
        state = Mutex(State(sources: stored))
    }

    func sources() -> AsyncStream<[MediaSource]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [MediaSource].self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { $0.observers[id] = nil }
        }
        state.withLock { state in
            state.observers[id] = continuation
            continuation.yield(state.sources)
        }
        return stream
    }

    func add(_ kind: SourceKind, _ login: SourceLogin) async throws(SourceError) -> MediaSource {
        let id = state.withLock { state in
            var id = SourceID.random()
            while state.sources.contains(where: { $0.id == id }) { id = SourceID.random() }
            return id
        }
        let (name, credential) = try await signIn(kind, login, for: id)
        let source = MediaSource(id: id, kind: kind, name: Redacted(name), endpoint: login.endpoint, username: login.username)
        try change { sources throws(SourceError) in
            try store.save(source, credential)
            sources.append(source)
        }
        Log.sources.info("added \(kind) source \(id)")
        return source
    }

    func update(
        _ id: SourceID, endpoint: SourceEndpoint, username: SourceUsername, password: PasswordChange
    ) async throws(SourceError) -> MediaSource {
        guard let current = state.withLock({ $0.sources.first { $0.id == id } }) else { throw .notFound }
        let name: String
        let credential: SourceCredential
        switch password {
        case .replace(let password):
            (name, credential) = try await signIn(current.kind, SourceLogin(endpoint: endpoint, username: username, password: password), for: id)
        case .keep:
            credential = try store.credential(for: id)
            name = try await check(credential, at: endpoint, as: username, for: id)
        }
        let source = MediaSource(id: id, kind: current.kind, name: Redacted(name), endpoint: endpoint, username: username)
        try change { sources throws(SourceError) in
            // Removed while signing in.
            guard let index = sources.firstIndex(where: { $0.id == id }) else { throw .notFound }
            try store.save(source, credential)
            sources[index] = source
        }
        Log.sources.info("updated source \(id)")
        return source
    }

    func remove(_ id: SourceID) async throws(SourceError) {
        try change { sources throws(SourceError) in
            try store.remove(id)
            sources.removeAll { $0.id == id }
        }
        Log.sources.info("removed source \(id)")
    }

    /// Lists the sources' add-ons in core now, before anything loads a model that would have to load
    /// again with them, then after every change.
    func keepListed(in core: CoreRuntime) {
        let changes = sources()
        Self.list(state.withLock { $0.sources }, in: core)
        // The first list `changes` yields is the one just listed, which core ignores as unchanged.
        Task {
            for await sources in changes {
                Self.list(sources, in: core)
            }
        }
    }

    private static func list(_ sources: [MediaSource], in core: CoreRuntime) {
        let descriptors = sources.compactMap { SourceAddonDescriptor(id: $0.id.rawValue, name: $0.name.rawValue, catalogs: []) }
        do {
            try core.setSources(descriptors)
            Log.sources.info("listed \(descriptors.count) source add-ons in core")
        } catch {
            Log.sources.error("listing the source add-ons failed: \(error)")
        }
    }

    func respond(to url: InProcessURL) async -> CoreFetchReply {
        let source = state.withLock { $0.sources.first { $0.id.rawValue == url.addonID } }
        guard let source, url.url.rawValue.path() == "/manifest.json",
              let descriptor = SourceAddonDescriptor(id: source.id.rawValue, name: source.name.rawValue, catalogs: []),
              let manifest = try? descriptor.encodedManifest()
        else { return CoreFetchReply(status: 404, body: Data()) }
        return CoreFetchReply(status: 200, body: manifest)
    }

    /// The sources offer no streams or subtitles yet.
    func playbackSource(for placeholder: InProcessURL) -> PlaybackSource? { nil }

    /// Signs in with `login`, returning the source's name and what to keep to sign in again.
    private func signIn(_ kind: SourceKind, _ login: SourceLogin, for id: SourceID) async throws(SourceError) -> (String, SourceCredential) {
        switch kind {
        case .jellyfin:
            let (serverName, session) = try await jellyfin.signIn(login, for: id)
            return (serverName, .jellyfin(session))
        case .webDAV:
            try await webDAV.check(login.endpoint, login.username, login.password)
            return (Self.folderName(login.endpoint), .webDAV(login.password))
        }
    }

    /// Signs in with a kept credential, returning the source's name.
    private func check(
        _ credential: SourceCredential, at endpoint: SourceEndpoint, as username: SourceUsername, for id: SourceID
    ) async throws(SourceError) -> String {
        switch credential {
        case .jellyfin(let session):
            return try await jellyfin.check(session, at: endpoint, as: username, for: id)
        case .webDAV(let password):
            try await webDAV.check(endpoint, username, password)
            return Self.folderName(endpoint)
        }
    }

    /// The folder's last path component, or the host for a server's root.
    private static func folderName(_ endpoint: SourceEndpoint) -> String {
        let url = endpoint.url.rawValue
        let folder = url.lastPathComponent
        return folder.isEmpty || folder == "/" ? url.host() ?? folder : folder
    }

    /// Applies `body` to the sources, storage included, and tells every observer when it succeeds.
    private func change(_ body: (inout [MediaSource]) throws(SourceError) -> Void) throws(SourceError) {
        try state.withLock { state throws(SourceError) in
            try body(&state.sources)
            state.observers.values.forEach { $0.yield(state.sources) }
        }
    }
}
