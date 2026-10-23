import CryptoKit
import Foundation

/// Turns a WebDAV listing into titles. Each top-level folder is a library of the kind the user
/// chose, else of the kind its videos suggest. A title is known by the IMDb id its `.nfo` file
/// holds (`<video>.nfo` or `movie.nfo` for a movie, `tvshow.nfo` for a show), else by the one in
/// its file's or a parent folder's name (`[imdbid-tt…]`, `{imdb-tt…}`), else by the one `matched`
/// gives its local id, else by a local id keyed by its path. A file named `S01E02` or `1x02` is an
/// episode of the show whose folder carries the id, or else of the folder above its `Season NN`
/// folder or its own.
struct WebDAVMatcher {
    static let videoExtensions: Set<String> = ["mkv", "mp4", "m4v", "mov", "avi", "webm", "ts"]
    static let subtitleExtensions: Set<String> = ["srt", "vtt", "ass", "ssa"]

    let source: SourceID
    /// The kinds the user chose, by library folder.
    var kinds: [LibraryFolder: FolderKind] = [:]
    /// IMDb ids read from `.nfo` files, by the file's path.
    var nfo: [WebDAVPath: MediaID] = [:]
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
        var searchable: [MediaID: SourceTitle] = [:]
        var libraries: [SourceIndex.Library] = []
        var suggestions: [FolderSuggestion] = []
        var titles: [MediaID: SourceTitle] = [:]
        for (name, found) in Dictionary(grouping: matches, by: \.library) {
            guard let id = Self.key(of: [name]), let folder = LibraryFolder(name) else { continue }
            let suggested = Self.suggestedKind(of: found.map(\.video.path))
            suggestions.append(FolderSuggestion(folder: folder, kind: suggested))
            let kind = kinds[folder] ?? suggested
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
                guard !title.id.rawValue.hasPrefix("tt") else { continue }
                localTitles[title.id] = title
                if kind.searchedTitles == title.kind { searchable[title.id] = title }
            }
            for (former, renamed) in Dictionary(grouping: found.filter { $0.title.formerID != nil }, by: \.title.formerID) {
                guard let former, let title = title(of: renamed, as: former) else { continue }
                localTitles[former] = title.title
            }
            let type: SourceTitle.Kind = kind == .shows ? .series : .movie
            libraries.append(SourceIndex.Library(id: id, name: Redacted(name), type: type, titles: libraryTitles))
        }
        libraries.sort { $0.name.rawValue.localizedStandardCompare($1.name.rawValue) == .orderedAscending }
        suggestions.sort { $0.folder.name.rawValue.localizedStandardCompare($1.folder.name.rawValue) == .orderedAscending }
        let videos = Dictionary(matches.map { ($0.key, $0.video) }) { first, _ in first }
        let index = SourceIndex(libraries: libraries, items: items, localTitles: localTitles, folders: folders(of: matches, titles: titles))
        return WebDAVListing(index: index, videos: videos, suggestions: suggestions, searchable: searchable)
    }

    /// The kind a library's videos suggest, by their paths: Shows when most are episodes
    /// (`S01E02`, `1x02`), Movies when most name a year in the file's name or carry an IMDb id
    /// tag, else Other Videos. Only the file's name counts for the year, since folders of home
    /// videos are often named for one, as in `Summer 2019`.
    static func suggestedKind(of videos: [WebDAVPath]) -> FolderKind {
        let bases = videos.compactMap { path in path.names.last.flatMap(split).map { (path: path, base: $0.base) } }
        func isMost(_ count: Int) -> Bool { count * 2 > bases.count }
        if isMost(bases.count(where: { episode(in: $0.base) != nil })) { return .shows }
        let named = bases.count(where: { video in ReleaseName(video.base).year != nil || video.path.names.contains { imdbID(in: $0) != nil } })
        return isMost(named) ? .movies : .otherVideos
    }

    /// The `.nfo` files that can name a title: `tvshow.nfo` in a folder of a library, `movie.nfo`
    /// in a movie's own folder, and `<video>.nfo` beside a video that is no episode. An episode's
    /// own `.nfo` names the episode, which plays under its show's id, so it is not read.
    static func nfoFiles(in entries: [WebDAVEntry]) -> [NfoFile] {
        let movies = Set(entries.compactMap { entry -> [String]? in
            guard let (base, ext) = entry.path.names.last.flatMap(split), videoExtensions.contains(ext), episode(in: base) == nil else { return nil }
            return Array(entry.path.names.dropLast()) + [base]
        })
        return entries.compactMap { entry in
            let names = entry.path.names
            guard case .file(let size) = entry.kind, names.count >= 2, let name = names.last, name.hasSuffix(".nfo") else { return nil }
            let base = String(name.dropLast(4))
            let root: NfoFile.Root? = if names.count >= 3 && name == "tvshow.nfo" {
                .tvshow
            } else if names.count >= 3 && name == "movie.nfo" || movies.contains(Array(names.dropLast()) + [base]) {
                .movie
            } else {
                nil
            }
            return root.map { NfoFile(path: entry.path, root: $0, size: size, modified: entry.modified) }
        }
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
    /// folders, and its id is the one that folder's `tvshow.nfo` holds, else its tag's. A file
    /// loose in the library belongs to the show its name begins with.
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
        let described = folder >= 1 ? nfo[WebDAVPath(names: path + ["tvshow.nfo"])] : nil
        guard let (id, formerID) = identity(described ?? place.imdb?.id, local: path) else { return nil }
        let rest = ReleaseName(String(place.base[marker.range.upperBound...])).title
        let episode = SourceEpisode(
            season: marker.season, episode: marker.episode, name: Redacted(rest.isEmpty ? "Episode \(marker.episode)" : rest),
            overview: nil, thumbnail: nil, released: nil
        )
        return Title(id: id, formerID: formerID, name: name, episode: episode, folder: nil)
    }

    /// A movie is the file its `<video>.nfo` names, else the folder its `movie.nfo` names, else the
    /// folder carrying its id or holding it alone, else the file itself.
    private func movie(of place: Place, isAlone: Bool) -> Title? {
        let folder = Array(place.names.dropLast())
        let own = nfo[WebDAVPath(names: folder + ["\(place.base).nfo"])].map { (id: $0, carrier: place.file) }
        let folders = place.file > 1 ? nfo[WebDAVPath(names: folder + ["movie.nfo"])].map { (id: $0, carrier: place.file - 1) } : nil
        let named = own ?? folders ?? place.imdb
        let carrier = named?.carrier ?? (place.file > 1 && isAlone ? place.file - 1 : place.file)
        let name = carrier == place.file ? place.base : place.names[carrier]
        guard let (id, formerID) = identity(named?.id, local: Array(place.names[...carrier])) else { return nil }
        return Title(id: id, formerID: formerID, name: name, episode: nil, folder: carrier < place.file ? carrier : nil)
    }

    /// The id a title is known by: the IMDb id its `.nfo` or tag names, else the one matched to
    /// the local id of `path` and that local id, else the local id.
    private func identity(_ named: MediaID?, local path: [String]) -> (id: MediaID, formerID: MediaID?)? {
        if let named { return (named, nil) }
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
        name.firstMatch(of: /(?i)[\[{]imdb(?:id)?-(tt\d+)[\]}]/).flatMap { MediaID.imdb($0.1.lowercased()) }
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

private extension FolderKind {
    /// The titles of this kind of folder that Cinemeta's search may name. None in Other Videos,
    /// whose names are the user's own.
    var searchedTitles: SourceTitle.Kind? {
        switch self {
        case .movies: .movie
        case .shows: .series
        case .otherVideos: nil
        }
    }
}
