import Foundation
import Synchronization

/// The user's media sources: signed in to when added or edited, kept in the Keychain, and listed in
/// core as in-process add-ons, one per source. A Jellyfin source's add-on (`JellyfinAddon`) offers
/// the server's films and shows and hears how they play; a WebDAV source's (`WebDAVAddon`) offers
/// the videos in its folders.
final class SourceLibrary: MediaSourceService, CoreInProcessAddons, CorePlaybackLinks, CorePlaybackReports {
    private struct State {
        var sources: [MediaSource]
        var observers: [UUID: AsyncStream<[MediaSource]>.Continuation] = [:]
        /// Made when first needed, and dropped when their source changes.
        var addons: [SourceID: ServerAddon] = [:]
        /// Asks for the add-ons to be listed in core again, once `keepListed` runs.
        var relist: AsyncStream<Void>.Continuation?
    }

    private let store: KeychainSourceStore
    private let jellyfin: JellyfinClient
    private let webDAV: WebDAVClient
    private let state: Mutex<State>
    private let playbackEvents: AsyncStream<InProcessPlayback>.Continuation

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
        let (events, playbackEvents) = AsyncStream.makeStream(of: InProcessPlayback.self)
        self.playbackEvents = playbackEvents
        Task { [weak self] in
            var reports = JellyfinPlaybackReports()
            for await event in events {
                for report in reports.reports(after: event, at: .now) {
                    guard case .jellyfin(let addon) = self?.addon(for: report.source) else { continue }
                    await addon.report(report)
                }
            }
        }
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
        let source = MediaSource(id: id, kind: kind, name: name, endpoint: login.endpoint, username: login.username)
        try change { state throws(SourceError) in
            try store.save(source, credential)
            state.sources.append(source)
        }
        Log.sources.info("added \(kind) source \(id)")
        return source
    }

    func update(_ id: SourceID, _ edit: SourceEdit) async throws(SourceError) -> MediaSource {
        guard let current = state.withLock({ $0.sources.first { $0.id == id } }) else { throw .notFound }
        let credential: SourceCredential
        switch edit.password {
        case .replace(let password):
            (_, credential) = try await signIn(current.kind, SourceLogin(endpoint: edit.endpoint, username: edit.username, password: password), for: id)
        case .keep:
            credential = try store.credential(for: id)
            try await check(credential, at: edit.endpoint, as: edit.username, for: id)
        }
        let source = MediaSource(id: id, kind: current.kind, name: edit.name, endpoint: edit.endpoint, username: edit.username)
        try change { state throws(SourceError) in
            // Removed while signing in.
            guard let index = state.sources.firstIndex(where: { $0.id == id }) else { throw .notFound }
            try store.save(source, credential)
            state.sources[index] = source
            state.addons[id] = nil
        }
        Log.sources.info("updated source \(id)")
        return source
    }

    func remove(_ id: SourceID) async throws(SourceError) {
        try change { state throws(SourceError) in
            try store.remove(id)
            state.sources.removeAll { $0.id == id }
            state.addons[id] = nil
        }
        Log.sources.info("removed source \(id)")
    }

    func browse(_ id: SourceID, folder: SourceFolderID?) async throws(SourceError) -> [SourceEntry] {
        guard let addon = addon(for: id) else { throw .notFound }
        return try await addon.listed.browse(folder)
    }

    /// Lists the sources' add-ons in core now, before anything loads a model that would have to load
    /// again with them, then after every change to the sources or their catalogs. Each listing reads
    /// the indexes that are missing or old, so a source's catalogs follow its libraries.
    func keepListed(in core: CoreRuntime) {
        let (requests, relist) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        state.withLock { $0.relist = relist }
        list(in: core)
        Task { [weak self] in
            for await _ in requests {
                self?.list(in: core)
            }
        }
    }

    private func list(in core: CoreRuntime) {
        let sources = state.withLock { $0.sources }
        let addons = sources.compactMap { addon(for: $0.id)?.listed }
        let descriptors = sources.compactMap { source in
            addons.first { $0.source.id == source.id }?.descriptor
                ?? SourceAddonDescriptor(id: source.id.rawValue, name: source.name.text.rawValue, catalogs: [])
        }
        do {
            try core.setSources(descriptors)
            Log.sources.info("listed \(descriptors.count) source add-ons in core, \(descriptors.map(\.catalogs.count)) catalogs")
        } catch {
            Log.sources.error("listing the source add-ons failed: \(error)")
        }
        for addon in addons {
            Task { _ = try? await addon.index() }
        }
    }

    func respond(to url: InProcessURL) async -> CoreFetchReply {
        guard let id = SourceID(url.addonID) else { return SourceAddonReplies.notFound }
        if let addon = addon(for: id) {
            return await addon.listed.respond(to: url)
        }
        let source = state.withLock { $0.sources.first { $0.id == id } }
        guard let source, SourceAddonRequest(url) == .manifest,
              let manifest = try? SourceAddonDescriptor(id: source.id.rawValue, name: source.name.text.rawValue, catalogs: [])?.encodedManifest()
        else { return SourceAddonReplies.notFound }
        return CoreFetchReply(status: 200, body: manifest)
    }

    func playbackSource(for placeholder: InProcessURL) -> PlaybackSource? {
        guard let id = SourceID(placeholder.addonID), let addon = addon(for: id), let link = SourcePlaceholder(placeholder) else { return nil }
        return addon.listed.playbackSource(for: link)
    }

    func playback(_ event: InProcessPlayback) {
        playbackEvents.yield(event)
    }

    /// The source's add-on, made with the stored sign-in when first needed.
    private func addon(for id: SourceID) -> ServerAddon? {
        state.withLock { state in
            if let addon = state.addons[id] { return addon }
            guard let source = state.sources.first(where: { $0.id == id }) else { return nil }
            let credential: SourceCredential
            do {
                credential = try store.credential(for: id)
            } catch {
                Log.sources.error("reading the sign-in of source \(id) failed: \(error)")
                return nil
            }
            let relist: @Sendable () -> Void = { [weak self] in
                self?.state.withLock { $0.relist }?.yield()
            }
            let addon: ServerAddon = switch credential {
            case .jellyfin(let session): .jellyfin(JellyfinAddon(source: source, session: session, client: jellyfin, catalogsChanged: relist))
            case .webDAV(let password): .webDAV(WebDAVAddon(source: source, password: password, client: webDAV, catalogsChanged: relist))
            }
            state.addons[id] = addon
            return addon
        }
    }

    /// Signs in with `login`, returning the server's name for the source and what to keep to sign in again.
    private func signIn(_ kind: SourceKind, _ login: SourceLogin, for id: SourceID) async throws(SourceError) -> (SourceName, SourceCredential) {
        switch kind {
        case .jellyfin:
            let (serverName, session) = try await jellyfin.signIn(login, for: id)
            return (SourceName(serverName) ?? SourceName(hostOf: login.endpoint), .jellyfin(session))
        case .webDAV:
            try await webDAV.check(login.endpoint, login.username, login.password)
            return (Self.folderName(login.endpoint), .webDAV(login.password))
        }
    }

    /// Signs in with a kept credential.
    private func check(
        _ credential: SourceCredential, at endpoint: SourceEndpoint, as username: SourceUsername, for id: SourceID
    ) async throws(SourceError) {
        switch credential {
        case .jellyfin(let session):
            _ = try await jellyfin.check(session, at: endpoint, as: username, for: id)
        case .webDAV(let password):
            try await webDAV.check(endpoint, username, password)
        }
    }

    /// The folder's last path component, or the host for a server's root.
    private static func folderName(_ endpoint: SourceEndpoint) -> SourceName {
        let folder = endpoint.url.rawValue.lastPathComponent
        return folder == "/" ? SourceName(hostOf: endpoint) : SourceName(folder) ?? SourceName(hostOf: endpoint)
    }

    /// Applies `body` to the sources, storage included, and tells every observer and core when it succeeds.
    private func change(_ body: (inout State) throws(SourceError) -> Void) throws(SourceError) {
        try state.withLock { state throws(SourceError) in
            try body(&state)
            state.observers.values.forEach { $0.yield(state.sources) }
            state.relist?.yield()
        }
    }
}

/// A source's add-on, by the kind of its server.
private enum ServerAddon: Sendable {
    /// Also hears what plays, for the server's resume position and watched state.
    case jellyfin(JellyfinAddon)
    case webDAV(WebDAVAddon)

    var listed: any ListedSourceAddon {
        switch self {
        case .jellyfin(let addon): addon
        case .webDAV(let addon): addon
        }
    }
}
