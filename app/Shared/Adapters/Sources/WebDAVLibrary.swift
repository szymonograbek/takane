import Foundation

/// A WebDAV source's add-on. WebDAV has no watched state, so progress lives in core's library alone.
typealias WebDAVAddon = SourceAddon<WebDAVConnection>

extension SourceAddon where Server == WebDAVConnection {
    convenience init(
        source: MediaSource,
        password: Password,
        client: WebDAVClient,
        titles: TitleMatcher,
        nfo: NfoReader = NfoReader(),
        matchingBudget: Duration = .seconds(3),
        lifetime: Duration = indexLifetime,
        catalogsChanged: @escaping @Sendable () -> Void
    ) {
        let folder = WebDAVFolder(endpoint: source.endpoint, username: source.username, password: password)
        let server = WebDAVConnection(
            source: source.id, kinds: source.folderKinds, client: client, folder: folder, titles: titles, nfo: nfo, matchingBudget: matchingBudget
        )
        self.init(source: source, server: server, lifetime: lifetime, catalogsChanged: catalogsChanged)
    }

    /// The library folders of the latest listing, read now when there is none or it is old.
    func folderSuggestions() async throws(SourceError) -> [FolderSuggestion] {
        try await listing().suggestions
    }
}

/// A WebDAV folder as its add-on reads it: one listing of every file, matched into titles.
struct WebDAVConnection: SourceServer {
    let source: SourceID
    let kinds: [LibraryFolder: FolderKind]
    let client: WebDAVClient
    let folder: WebDAVFolder
    let titles: TitleMatcher
    let nfo: NfoReader
    /// How long a listing waits for the `.nfo` files, then again for Cinemeta to name the titles
    /// that have no id. Core's catalogs wait for the listing, and an uncached search can take
    /// seconds, so titles still read or looked up then keep the ids they would have without, until
    /// a later listing finds them.
    let matchingBudget: Duration

    func list() async throws(SourceError) -> WebDAVListing {
        let entries = try await client.list(folder)
        let ids = await nfo.ids(of: WebDAVMatcher.nfoFiles(in: entries), in: folder, client: client, within: matchingBudget)
        var matcher = WebDAVMatcher(source: source, kinds: kinds, nfo: ids)
        let unmatched = matcher.listing(of: entries)
        let queries = unmatched.searchable.compactMapValues(TitleQuery.init)
        guard !queries.isEmpty else { return unmatched }
        let found = await titles.ids(for: Set(queries.values), within: matchingBudget)
        matcher.matched = queries.compactMapValues { found[$0] }
        guard !matcher.matched.isEmpty else { return unmatched }
        return matcher.listing(of: entries)
    }

    func files(of id: PlayableID, in listing: WebDAVListing) -> [SourceFile] {
        (listing.index.items[id] ?? []).compactMap { listing.videos[$0]?.file }
    }

    /// Placeholders name a video by a key of its path, so the listing that gave it finds the file.
    func playbackSource(for placeholder: SourcePlaceholder, in listing: WebDAVListing?) -> PlaybackSource? {
        let path: WebDAVPath? = switch placeholder {
        case .video(_, let file):
            listing?.videos[file]?.path
        case .subtitle(_, let file, let index):
            listing?.videos[file].flatMap { $0.subtitles.indices.contains(index) ? $0.subtitles[index] : nil }
        }
        return path.map { PlaybackSource(url: Redacted(folder.url(of: $0)), headers: ["Authorization": folder.authorization]) }
    }
}

/// What a WebDAV source offers: its index, and where each video and its subtitles are.
struct WebDAVListing: SourceListing {
    let index: SourceIndex
    let videos: [SourceItemID: WebDAVVideo]
    /// Each library folder with the kind its videos suggest, by name.
    let suggestions: [FolderSuggestion]
    /// The titles with a local id that Cinemeta's search may name, by that id: films in Movies
    /// folders and shows in Shows folders.
    let searchable: [MediaID: SourceTitle]
}

struct WebDAVVideo: Equatable, Sendable {
    let path: WebDAVPath
    let file: SourceFile
    /// The paths of `file.subtitles`, in their order.
    let subtitles: [WebDAVPath]
}
