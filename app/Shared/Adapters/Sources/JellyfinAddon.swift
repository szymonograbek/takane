import Foundation
import Synchronization

/// One Jellyfin source as a Stremio add-on. It answers core's requests from an index of the
/// server's libraries, read when first asked for and again once older than `lifetime`, offers one
/// catalog per library, and turns its placeholders into the server's files.
final class JellyfinAddon: Sendable {
    /// How long an index answers before the next request reads the server again.
    static let indexLifetime = Duration.seconds(300)

    let source: MediaSource
    private let server: JellyfinServer
    private let client: JellyfinClient
    private let lifetime: Duration
    /// Called when a new index brings other catalogs, so core lists them.
    private let catalogsChanged: @Sendable () -> Void
    private let state = Mutex(State())

    private struct State {
        var index = IndexState.unread
        /// From the last index read, kept while the next one is read.
        var catalogs: [SourceAddonDescriptor.Catalog] = []
    }

    private enum IndexState {
        case unread
        case reading(Task<Result<SourceIndex, SourceError>, Never>)
        case read(SourceIndex, at: ContinuousClock.Instant)
    }

    init(
        source: MediaSource,
        session: JellyfinSession,
        client: JellyfinClient,
        lifetime: Duration = indexLifetime,
        catalogsChanged: @escaping @Sendable () -> Void
    ) {
        self.source = source
        server = JellyfinServer(source: source.id, endpoint: source.endpoint, session: session)
        self.client = client
        self.lifetime = lifetime
        self.catalogsChanged = catalogsChanged
    }

    /// The add-on as core lists it, with the catalogs of the last index read: none before the first.
    var descriptor: SourceAddonDescriptor? {
        SourceAddonDescriptor(id: source.id.rawValue, name: source.name.rawValue, catalogs: state.withLock { $0.catalogs })
    }

    func respond(to url: InProcessURL) async -> CoreFetchReply {
        guard let request = SourceAddonRequest(url), let descriptor else { return SourceAddonReplies.notFound }
        let replies = SourceAddonReplies(addon: descriptor)
        do {
            switch request {
            case .manifest:
                return CoreFetchReply(status: 200, body: try descriptor.encodedManifest())
            case .catalog(let library, let search):
                guard let found = try await index().libraries.first(where: { $0.id == library }) else { return SourceAddonReplies.notFound }
                return replies.catalog(found, search: search)
            case .meta(let id):
                guard let title = try await index().localTitles[id] else { return SourceAddonReplies.notFound }
                return replies.meta(title)
            case .streams(let id):
                return replies.streams(try await files(of: id))
            case .subtitles(let id):
                return replies.subtitles(try await files(of: id))
            }
        } catch {
            Log.sources.error("source \(source.id) could not answer \(url.url): \(error)")
            return CoreFetchReply(status: 502, body: Data())
        }
    }

    func playbackSource(for placeholder: SourcePlaceholder) -> PlaybackSource {
        switch placeholder {
        case .video(let item, let file): client.video(item, file: file, on: server)
        case .subtitle(let item, let file, let index): client.subtitle(item, file: file, index: index, on: server)
        }
    }

    func report(_ report: JellyfinPlaybackReport) async {
        do {
            try await client.report(report, to: server)
            Log.sources.debug("reported \(report.kind) at \(report.position) to source \(source.id)")
        } catch {
            Log.sources.warning("reporting \(report.kind) to source \(source.id) failed: \(error)")
        }
    }

    /// The current index, read from the server when there is none or it is older than `lifetime`.
    /// Requests that arrive while it is read wait for the same read.
    func index() async throws(SourceError) -> SourceIndex {
        let reading = state.withLock { state -> IndexRead in
            switch state.index {
            case .read(let index, let at) where ContinuousClock.now - at < lifetime:
                return .ready(index)
            case .reading(let task):
                return .waiting(task)
            case .unread, .read:
                let task = Task { [client, server] in
                    do throws(SourceError) {
                        return Result<SourceIndex, SourceError>.success(try await client.index(of: server))
                    } catch {
                        return .failure(error)
                    }
                }
                state.index = .reading(task)
                return .waiting(task)
            }
        }
        switch reading {
        case .ready(let index):
            return index
        case .waiting(let task):
            let result = await task.value
            finish(task, with: result)
            return try result.get()
        }
    }

    private enum IndexRead {
        case ready(SourceIndex)
        case waiting(Task<Result<SourceIndex, SourceError>, Never>)
    }

    /// Keeps the index `task` read, unless another read replaced it, and forgets a failed read so
    /// the next request tries again.
    private func finish(_ task: Task<Result<SourceIndex, SourceError>, Never>, with result: Result<SourceIndex, SourceError>) {
        let changed = state.withLock { state -> Bool in
            guard case .reading(let current) = state.index, current == task else { return false }
            switch result {
            case .success(let index):
                state.index = .read(index, at: .now)
                let catalogs = index.libraries.map { library in
                    SourceAddonDescriptor.Catalog(type: library.type.name, id: library.id.rawValue, name: library.name.rawValue, searchable: true)
                }
                defer { state.catalogs = catalogs }
                return catalogs != state.catalogs
            case .failure(let error):
                Log.sources.error("reading source \(source.id) failed: \(error)")
                state.index = .unread
                return false
            }
        }
        if changed { catalogsChanged() }
    }

    private func files(of id: PlayableID) async throws(SourceError) -> [SourceFile] {
        let items = try await index().items[id] ?? []
        return try await client.files(of: items, on: server)
    }
}
