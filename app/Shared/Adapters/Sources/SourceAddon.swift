import Foundation
import Synchronization

/// What a source's add-on needs of its server: a full listing of it, the files of a title, and the
/// file a placeholder stands for.
protocol SourceServer: Sendable {
    /// One full listing of the server: the add-on's index, with whatever else finds its files.
    associatedtype Listing: SourceListing

    func list() async throws(SourceError) -> Listing
    /// The files that play `id`, in `listing`'s order.
    func files(of id: PlayableID, in listing: Listing) async throws(SourceError) -> [SourceFile]
    /// `listing` is the latest one read, nil before the first. Nil when it names no file.
    func playbackSource(for placeholder: SourcePlaceholder, in listing: Listing?) -> PlaybackSource?
}

protocol SourceListing: Sendable {
    var index: SourceIndex { get }
}

/// A source's add-on as `SourceLibrary` lists and asks it, whatever its server.
protocol ListedSourceAddon: Sendable {
    var source: MediaSource { get }
    var descriptor: SourceAddonDescriptor? { get }
    func respond(to url: InProcessURL) async -> CoreFetchReply
    func playbackSource(for placeholder: SourcePlaceholder) -> PlaybackSource?
    func index() async throws(SourceError) -> SourceIndex
    func browse(_ folder: SourceFolderID?) async throws(SourceError) -> [SourceEntry]
}

/// One source as a Stremio add-on. It answers core's requests from a listing of the server, read
/// when first asked for and again once older than `lifetime`, offers one searchable catalog per
/// library, and turns its placeholders into the server's files.
final class SourceAddon<Server: SourceServer>: ListedSourceAddon {
    /// How long a listing answers before the next request reads the server again.
    static var indexLifetime: Duration { .seconds(300) }

    let source: MediaSource
    let server: Server
    private let lifetime: Duration
    /// Called when a new listing brings other catalogs, so core lists them.
    private let catalogsChanged: @Sendable () -> Void
    private let state = Mutex(State())

    private struct State {
        var listing = ListingState.unread
        /// The last listing read, kept while the next one is read and after one fails, so the
        /// catalogs stay listed and placeholders still play.
        var latest: Server.Listing?
    }

    private enum ListingState {
        case unread
        case reading(Task<Result<Server.Listing, SourceError>, Never>)
        case read(Server.Listing, at: ContinuousClock.Instant)
    }

    init(source: MediaSource, server: Server, lifetime: Duration = indexLifetime, catalogsChanged: @escaping @Sendable () -> Void) {
        self.source = source
        self.server = server
        self.lifetime = lifetime
        self.catalogsChanged = catalogsChanged
    }

    /// The add-on as core lists it, with the catalogs of the last listing read: none before the first.
    var descriptor: SourceAddonDescriptor? {
        SourceAddonDescriptor(id: source.id.rawValue, name: source.name.text.rawValue, catalogs: Self.catalogs(of: state.withLock { $0.latest }))
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
                return replies.streams(try await server.files(of: id, in: listing()))
            case .subtitles(let id):
                return replies.subtitles(try await server.files(of: id, in: listing()))
            }
        } catch {
            Log.sources.error("source \(source.id) could not answer \(url.url): \(error)")
            return CoreFetchReply(status: 502, body: Data())
        }
    }

    func playbackSource(for placeholder: SourcePlaceholder) -> PlaybackSource? {
        server.playbackSource(for: placeholder, in: state.withLock { $0.latest })
    }

    func index() async throws(SourceError) -> SourceIndex {
        try await listing().index
    }

    func browse(_ folder: SourceFolderID?) async throws(SourceError) -> [SourceEntry] {
        guard let entries = try await index().folders.entries(in: folder) else { throw .folderGone }
        return entries
    }

    /// The current listing, read from the server when there is none or it is older than `lifetime`.
    /// Requests that arrive while it is read wait for the same read.
    private func listing() async throws(SourceError) -> Server.Listing {
        let reading = state.withLock { state -> ListingRead in
            switch state.listing {
            case .read(let listing, let at) where ContinuousClock.now - at < lifetime:
                return .ready(listing)
            case .reading(let task):
                return .waiting(task)
            case .unread, .read:
                let task = Task { [server] in
                    do throws(SourceError) {
                        return Result<Server.Listing, SourceError>.success(try await server.list())
                    } catch {
                        return .failure(error)
                    }
                }
                state.listing = .reading(task)
                return .waiting(task)
            }
        }
        switch reading {
        case .ready(let listing):
            return listing
        case .waiting(let task):
            let result = await task.value
            finish(task, with: result)
            return try result.get()
        }
    }

    private enum ListingRead {
        case ready(Server.Listing)
        case waiting(Task<Result<Server.Listing, SourceError>, Never>)
    }

    /// Keeps the listing `task` read, unless another read replaced it, and forgets a failed read so
    /// the next request tries again.
    private func finish(_ task: Task<Result<Server.Listing, SourceError>, Never>, with result: Result<Server.Listing, SourceError>) {
        let changed = state.withLock { state -> Bool in
            guard case .reading(let current) = state.listing, current == task else { return false }
            switch result {
            case .success(let listing):
                let changed = Self.catalogs(of: listing) != Self.catalogs(of: state.latest)
                state.listing = .read(listing, at: .now)
                state.latest = listing
                return changed
            case .failure(let error):
                Log.sources.error("reading source \(source.id) failed: \(error)")
                state.listing = .unread
                return false
            }
        }
        if changed { catalogsChanged() }
    }

    private static func catalogs(of listing: Server.Listing?) -> [SourceAddonDescriptor.Catalog] {
        (listing?.index.libraries ?? []).map { library in
            SourceAddonDescriptor.Catalog(type: library.type.name, id: library.id.rawValue, name: library.name.rawValue, searchable: true)
        }
    }
}
