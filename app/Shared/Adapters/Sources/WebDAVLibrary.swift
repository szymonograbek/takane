import CryptoKit
import Foundation

/// A WebDAV source's add-on. WebDAV has no watched state, so progress lives in core's library alone.
typealias WebDAVAddon = SourceAddon<WebDAVConnection>

extension SourceAddon where Server == WebDAVConnection {
    convenience init(
        source: MediaSource,
        password: Password,
        client: WebDAVClient,
        titles: TitleMatcher,
        matchingBudget: Duration = .seconds(3),
        lifetime: Duration = indexLifetime,
        catalogsChanged: @escaping @Sendable () -> Void
    ) {
        let folder = WebDAVFolder(endpoint: source.endpoint, username: source.username, password: password)
        let server = WebDAVConnection(source: source.id, client: client, folder: folder, titles: titles, matchingBudget: matchingBudget)
        self.init(source: source, server: server, lifetime: lifetime, catalogsChanged: catalogsChanged)
    }
}

/// A WebDAV folder as its add-on reads it: one listing of every file, matched into titles.
struct WebDAVConnection: SourceServer {
    let source: SourceID
    let client: WebDAVClient
    let folder: WebDAVFolder
    let titles: TitleMatcher
    /// How long a listing waits for Cinemeta to name its untagged titles. Core's catalogs wait for
    /// the listing, and an uncached search can take seconds, so titles still looked up then keep
    /// their local ids until a later listing finds them.
    let matchingBudget: Duration

    func list() async throws(SourceError) -> WebDAVListing {
        let entries = try await client.list(folder)
        let untagged = WebDAVMatcher(source: source).listing(of: entries)
        let queries = untagged.index.localTitles.compactMapValues(TitleQuery.init)
        guard !queries.isEmpty else { return untagged }
        let found = await titles.ids(for: Set(queries.values), within: matchingBudget)
        let matched = queries.compactMapValues { found[$0] }
        guard !matched.isEmpty else { return untagged }
        return WebDAVMatcher(source: source, matched: matched).listing(of: entries)
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
}

struct WebDAVVideo: Equatable, Sendable {
    let path: WebDAVPath
    let file: SourceFile
    /// The paths of `file.subtitles`, in their order.
    let subtitles: [WebDAVPath]
}

/// Turns a WebDAV listing into titles. Each top-level folder is a library. A title is known by the
/// IMDb id in its file's or a parent folder's name (`[imdbid-tt…]`, `{imdb-tt…}`), else by the one
/// `matched` gives its local id, else by a local id keyed by its path. A file named `S01E02` or
/// `1x02` is an episode of the show whose folder carries the id, or else of the folder above its
/// `Season NN` folder or its own.
struct WebDAVMatcher {
    static let videoExtensions: Set<String> = ["mkv", "mp4", "m4v", "mov", "avi", "webm", "ts"]
    static let subtitleExtensions: Set<String> = ["srt", "vtt", "ass", "ssa"]

    let source: SourceID
    /// IMDb ids found by name, keyed by the local id each title had without them.
    var matched: [MediaID: MediaID] = [:]

    /// A video file as matched to the title it plays.
    private struct Match {
        let library: String
        let title: Title
        let key: SourceItemID
        let video: WebDAVVideo
        let modified: Date
    }

    /// The title a video plays, and for an episode, which.
    private struct Title {
        let id: MediaID
        /// The local id of a title matched by name, still answered so what was watched under it opens.
        let formerID: MediaID?
        /// As the folder or file names it, tags and year included.
        let name: String
        let episode: SourceEpisode?
        /// For a movie that is a folder, the folder's place in the path, so browsing shows the folder as the movie.
        let folder: Int?
    }

    /// A video's place: its path's names, and which of them carries an IMDb id.
    private struct Place {
        let names: [String]
        let base: String
        let imdb: (id: MediaID, carrier: Int)?

        var file: Int { names.count - 1 }
    }

    func listing(of entries: [WebDAVEntry]) -> WebDAVListing {
        let files = entries.filter { $0.kind != .folder }
        let byFolder = Dictionary(grouping: files) { Array($0.path.names.dropLast()) }
        let matches = files.compactMap { match($0, besides: byFolder[Array($0.path.names.dropLast())] ?? []) }
        var items: [PlayableID: [SourceItemID]] = [:]
        var localTitles: [MediaID: SourceTitle] = [:]
        var libraries: [SourceIndex.Library] = []
        var titles: [MediaID: SourceTitle] = [:]
        for (name, found) in Dictionary(grouping: matches, by: \.library) {
            guard let id = Self.key(of: [name]) else { continue }
            for match in found {
                for media in [match.title.id, match.title.formerID].compactMap(\.self) {
                    let playable = match.title.episode.map { PlayableID.episode(media, season: $0.season, episode: $0.episode) } ?? .movie(media)
                    items[playable, default: []].append(match.key)
                }
            }
            let libraryTitles = Dictionary(grouping: found, by: \.title.id).compactMap { title(of: $1, as: $0) }
                .sorted(by: Self.newestFirst).map(\.title)
            for title in libraryTitles {
                titles[title.id] = title
                if !title.id.rawValue.hasPrefix("tt") { localTitles[title.id] = title }
            }
            for (former, renamed) in Dictionary(grouping: found.filter { $0.title.formerID != nil }, by: \.title.formerID) {
                guard let former, let title = title(of: renamed, as: former) else { continue }
                localTitles[former] = title.title
            }
            let type: SourceTitle.Kind = libraryTitles.contains { $0.kind == .series } ? .series : .movie
            libraries.append(SourceIndex.Library(id: id, name: Redacted(name), type: type, titles: libraryTitles))
        }
        libraries.sort { $0.name.rawValue.localizedStandardCompare($1.name.rawValue) == .orderedAscending }
        let videos = Dictionary(matches.map { ($0.key, $0.video) }) { first, _ in first }
        let index = SourceIndex(libraries: libraries, items: items, localTitles: localTitles, folders: folders(of: matches, titles: titles))
        return WebDAVListing(index: index, videos: videos)
    }

    /// Each video in its folder, by name: a movie that is a folder in that folder's place, an
    /// episode as its file, any other movie as its title.
    private func folders(of matches: [Match], titles: [MediaID: SourceTitle]) -> SourceFolders {
        var folders: [SourceFolders.Folder] = []
        var items: [(entry: SourceEntry, folder: SourceFolderID?)] = []
        let sorted = matches.sorted { one, other in
            one.video.path.names.lexicographicallyPrecedes(other.video.path.names) { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        for match in sorted {
            guard let preview = titles[match.title.id]?.preview else { continue }
            let names = match.video.path.names
            let path = Array(names[..<(match.title.folder ?? names.count - 1)])
            for depth in path.indices {
                guard let id = Self.folderID(of: path[...depth]) else { continue }
                folders.append(SourceFolders.Folder(id: id, name: Redacted(path[depth]), parent: depth == 0 ? nil : Self.folderID(of: path[..<depth])))
            }
            let entry: SourceEntry = match.title.episode.map { .episode(show: preview, season: $0.season, episode: $0.episode, name: $0.name) }
                ?? .title(preview)
            items.append((entry, path.isEmpty ? nil : Self.folderID(of: path[...])))
        }
        return SourceFolders(folders: folders, items: items)
    }

    private static func folderID(of path: ArraySlice<String>) -> SourceFolderID? {
        key(of: Array(path)).map { SourceFolderID($0.rawValue) }
    }

    private static func newestFirst(_ one: (title: SourceTitle, modified: Date), _ other: (title: SourceTitle, modified: Date)) -> Bool {
        guard one.modified == other.modified else { return one.modified > other.modified }
        return one.title.name.rawValue.localizedStandardCompare(other.title.name.rawValue) == .orderedAscending
    }

    /// The title that `matches`, the files of one title, make as `id`, with when its newest file changed.
    private func title(of matches: [Match], as id: MediaID) -> (title: SourceTitle, modified: Date)? {
        guard let first = matches.first?.title else { return nil }
        var seen: Set<[Int]> = []
        let episodes = matches.compactMap(\.title.episode)
            .filter { seen.insert([$0.season, $0.episode]).inserted }
            .sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
        let name = ReleaseName(first.name)
        let title = SourceTitle(
            id: id, kind: first.episode == nil ? .movie : .series, name: Redacted(name.title.isEmpty ? first.name : name.title),
            poster: first.id.rawValue.hasPrefix("tt") ? SourceTitle.cinemetaPoster(of: first.id).map(Redacted.init) : nil,
            isLandscape: false, background: nil, overview: nil, year: name.year, episodes: episodes
        )
        return (title, matches.map(\.modified).max() ?? .distantPast)
    }

    /// Matches a video in a library to its title. Other files, and files outside a library, match nothing.
    private func match(_ entry: WebDAVEntry, besides neighbours: [WebDAVEntry]) -> Match? {
        let names = entry.path.names
        guard names.count >= 2, let (base, ext) = Self.split(names[names.count - 1]), Self.videoExtensions.contains(ext),
              let key = Self.key(of: names)
        else { return nil }
        let imdb = ([base] + names.dropFirst().dropLast().reversed()).lazy.enumerated()
            .compactMap { offset, name in Self.imdbID(in: name).map { (id: $0, carrier: names.count - 1 - offset) } }.first
        let place = Place(names: names, base: base, imdb: imdb)
        let sidecars = subtitles(of: base, among: neighbours)
        let video = WebDAVVideo(path: entry.path, file: file(entry, key: key, base: base, sidecars: sidecars), subtitles: sidecars)
        let title: Title?
        if let marker = Self.episode(in: base) {
            title = show(of: place, marker)
        } else {
            let videosBeside = neighbours.filter { Self.split($0.path.names.last ?? "").map { Self.videoExtensions.contains($0.ext) } ?? false }
            title = movie(of: place, isAlone: videosBeside.count == 1)
        }
        guard let title else { return nil }
        return Match(library: names[0], title: title, key: key, video: video, modified: entry.modified ?? .distantPast)
    }

    /// An episode's show is the nearest folder carrying an id, else the folder above its season
    /// folders. A file loose in the library belongs to the show its name begins with.
    private func show(of place: Place, _ marker: EpisodeMarker) -> Title? {
        let names = place.names
        var folder = place.file - 1
        if let imdb = place.imdb, imdb.carrier < place.file {
            folder = imdb.carrier
        } else {
            while folder >= 1, Self.isSeasonFolder(names[folder]) { folder -= 1 }
        }
        let name = folder >= 1 ? names[folder] : String(place.base[..<marker.range.lowerBound])
        let path = folder >= 1 ? Array(names[...folder]) : [names[0], Self.cleaned(name)]
        guard let (id, formerID) = identity(of: place, local: path) else { return nil }
        let rest = ReleaseName(String(place.base[marker.range.upperBound...])).title
        let episode = SourceEpisode(
            season: marker.season, episode: marker.episode, name: Redacted(rest.isEmpty ? "Episode \(marker.episode)" : rest),
            overview: nil, thumbnail: nil, released: nil
        )
        return Title(id: id, formerID: formerID, name: name, episode: episode, folder: nil)
    }

    /// A movie is the folder carrying its id or holding it alone, else the file itself.
    private func movie(of place: Place, isAlone: Bool) -> Title? {
        let carrier = place.imdb?.carrier ?? (place.file > 1 && isAlone ? place.file - 1 : place.file)
        let name = carrier == place.file ? place.base : place.names[carrier]
        guard let (id, formerID) = identity(of: place, local: Array(place.names[...carrier])) else { return nil }
        return Title(id: id, formerID: formerID, name: name, episode: nil, folder: carrier < place.file ? carrier : nil)
    }

    /// The id a title is known by: its tagged IMDb id, else the one matched to the local id of
    /// `path` and that local id, else the local id.
    private func identity(of place: Place, local path: [String]) -> (id: MediaID, formerID: MediaID?)? {
        if let imdb = place.imdb { return (imdb.id, nil) }
        guard let local = Self.key(of: path).flatMap({ MediaID.local($0, on: source) }) else { return nil }
        return matched[local].map { ($0, local) } ?? (local, nil)
    }

    private func file(_ entry: WebDAVEntry, key: SourceItemID, base: String, sidecars: [WebDAVPath]) -> SourceFile {
        let size: Int? = switch entry.kind {
        case .file(let size): size
        case .folder: nil
        }
        let subtitles = sidecars.enumerated().map { index, path in
            SourceSubtitle(index: index, language: Self.language(of: path, base: base), label: Redacted(path.names.last ?? ""))
        }
        return SourceFile(item: key, file: key, name: Redacted(entry.path.names.last ?? ""), quality: nil, size: size, subtitles: subtitles)
    }

    /// `<base>.srt`, `<base>.en.srt` and the like beside the video.
    private func subtitles(of base: String, among neighbours: [WebDAVEntry]) -> [WebDAVPath] {
        neighbours.map(\.path).filter { path in
            guard let name = path.names.last, let (rest, ext) = Self.split(name), Self.subtitleExtensions.contains(ext) else { return false }
            return rest == base || rest.hasPrefix("\(base).")
        }
        .sorted { ($0.names.last ?? "") < ($1.names.last ?? "") }
    }

    /// ISO 639-2 from the first of `.en`, `.eng` and the like between the video's name and the extension.
    private static func language(of path: WebDAVPath, base: String) -> String? {
        guard let name = path.names.last, let (rest, _) = split(name) else { return nil }
        return rest.dropFirst(base.count).split(separator: ".").lazy.compactMap { tag -> String? in
            guard (2...3).contains(tag.count), tag.allSatisfy(\.isLetter) else { return nil }
            return Locale.LanguageCode(String(tag).lowercased()).identifier(.alpha3)
        }.first
    }

    /// A name and its lowercased extension.
    private static func split(_ name: String) -> (base: String, ext: String)? {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        return (String(name[..<dot]), name[name.index(after: dot)...].lowercased())
    }

    /// A stable key of a path, letters and digits, so a title keeps its local id and a file its
    /// placeholder across listings, and an edited folder URL keeps both.
    private static func key(of names: [String]) -> SourceItemID? {
        let digest = SHA256.hash(data: Data(names.joined(separator: "/").utf8))
        return SourceItemID(digest.prefix(16).map { String(format: "%02x", $0) }.joined())
    }

    private static func imdbID(in name: String) -> MediaID? {
        name.firstMatch(of: /(?i)[\[{]imdb(?:id)?-(tt\d{7,9})[\]}]/).flatMap { MediaID($0.1.lowercased()) }
    }

    /// `S01E02` or `1x02` in a file's name.
    private struct EpisodeMarker {
        let season: Int
        let episode: Int
        let range: Range<String.Index>
    }

    private static func episode(in name: String) -> EpisodeMarker? {
        // Simple word boundaries, so `Show.S01E02` breaks at the dot.
        let found = name.firstMatch(of: /(?i)\bS(\d{1,3})[ ._-]?E(\d{1,4})/.wordBoundaryKind(.simple)).map { ($0.output.1, $0.output.2, $0.range) }
            ?? name.firstMatch(of: /\b(\d{1,2})x(\d{2,3})\b/.wordBoundaryKind(.simple)).map { ($0.output.1, $0.output.2, $0.range) }
        guard let found, let season = Int(found.0), let episode = Int(found.1) else { return nil }
        return EpisodeMarker(season: season, episode: episode, range: found.2)
    }

    private static func isSeasonFolder(_ name: String) -> Bool {
        name.wholeMatch(of: /(?i)(season|series|staffel|saison)?\s*\d{1,3}|s\d{1,3}|specials/) != nil
    }

    /// The name of a show loose in its library without its tags and year, which its local id's key
    /// hashes: `Show (2010).` is `Show`.
    private static func cleaned(_ name: String) -> String {
        let bare = name.replacing(/\[[^\]]*\]|\{[^}]*\}|\(\d{4}\)/, with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -._"))
        return bare.isEmpty ? name : bare
    }
}
