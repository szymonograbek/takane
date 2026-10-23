import Foundation

/// A Jellyfin source's add-on. It also tells the server what plays, so the server's resume position
/// and watched state follow Takane.
typealias JellyfinAddon = SourceAddon<JellyfinConnection>

/// A Jellyfin server this device is signed in to, as its add-on reads it: the index of its video
/// libraries, then a title's files when they are asked for.
struct JellyfinConnection: SourceServer {
    let client: JellyfinClient
    let server: JellyfinServer

    func list() async throws(SourceError) -> SourceIndex {
        try await client.index(of: server)
    }

    func files(of id: PlayableID, in index: SourceIndex) async throws(SourceError) -> [SourceFile] {
        try await client.files(of: index.items[id] ?? [], on: server)
    }

    /// Jellyfin's ids name its files, so no listing is needed.
    func playbackSource(for placeholder: SourcePlaceholder, in _: SourceIndex?) -> PlaybackSource? {
        switch placeholder {
        case .video(let item, let file): client.video(item, file: file, on: server)
        case .subtitle(let item, let file, let index): client.subtitle(item, file: file, index: index, on: server)
        }
    }
}

extension SourceIndex: SourceListing {
    var index: SourceIndex { self }
}

extension SourceAddon where Server == JellyfinConnection {
    convenience init(
        source: MediaSource,
        session: JellyfinSession,
        client: JellyfinClient,
        lifetime: Duration = indexLifetime,
        catalogsChanged: @escaping @Sendable () -> Void
    ) {
        let server = JellyfinServer(source: source.id, endpoint: source.endpoint, session: session)
        self.init(source: source, server: JellyfinConnection(client: client, server: server), lifetime: lifetime, catalogsChanged: catalogsChanged)
    }

    func report(_ report: JellyfinPlaybackReport) async {
        do {
            try await server.client.report(report, to: server.server)
            Log.sources.debug("reported \(report.kind) at \(report.position) to source \(source.id)")
        } catch {
            Log.sources.warning("reporting \(report.kind) to source \(source.id) failed: \(error)")
        }
    }
}
