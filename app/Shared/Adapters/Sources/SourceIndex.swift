import Foundation

/// A source server's own id for an item or one of its files, such as a Jellyfin item id, or a key
/// of a WebDAV path. Letters and digits only, so it is safe in a placeholder's path and inside a local id.
struct SourceItemID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init?(_ text: String) {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        rawValue = text
    }

    var description: String { rawValue }
}

extension MediaID {
    /// `takane-<source>-<key>`: a title only this source has, which only its add-on gives details of.
    static func local(_ key: SourceItemID, on source: SourceID) -> MediaID? {
        MediaID("\(SourceAddonDescriptor.localIDPrefix)\(source.rawValue)-\(key)")
    }

    /// An IMDb id as a file, a folder's name or an `.nfo` file writes it: `tt` and seven to nine digits.
    static func imdb(_ text: String) -> MediaID? {
        guard text.wholeMatch(of: /tt\d{7,9}/) != nil else { return nil }
        return MediaID(text)
    }
}

/// What a source's add-on offers, read from a full listing of its libraries: the catalogs, the
/// metadata of the titles only it has, and which items play what.
struct SourceIndex: Equatable, Sendable {
    /// A library, which the add-on offers as one catalog.
    struct Library: Equatable, Sendable {
        let id: SourceItemID
        let name: Redacted<String>
        let type: SourceTitle.Kind
        /// Its movies, shows and videos, in the server's order.
        let titles: [SourceTitle]
    }

    let libraries: [Library]
    /// The items that play a movie or an episode, keyed by its IMDb id when the server knows it,
    /// else by its local id.
    let items: [PlayableID: [SourceItemID]]
    /// The titles found only on this source, by their local id, and the titles matched by name
    /// under the local id they had before, so what was watched under it still opens.
    let localTitles: [MediaID: SourceTitle]
    /// The libraries and folders the titles are in, for browsing.
    let folders: SourceFolders
}

extension SourceIndex {
    /// The titles of every library, of `type` or of every type, in `sort`'s order. A title in two
    /// libraries shows once, where `sort` puts it first: its newest copy, or the one with a year.
    func titles(of type: ContentType?, sortedBy sort: SourceSort) -> [SourceTitle] {
        var seen: Set<MediaID> = []
        return libraries.flatMap(\.titles)
            .filter { title in type.map { $0 == title.kind.contentType } ?? true }
            .sorted(by: sort)
            .filter { seen.insert($0.id).inserted }
    }
}

extension [SourceTitle] {
    /// How many titles a page holds, a catalog's or the source's, as add-ons page theirs.
    static var pageSize: Int { 100 }

    /// Ties go by name, then by id, so a page always starts where the one before it ended.
    func sorted(by sort: SourceSort) -> [SourceTitle] {
        sorted { one, other in
            switch sort {
            case .recentlyAdded where one.added != other.added:
                return (one.added ?? .distantPast) > (other.added ?? .distantPast)
            case .year where one.year != other.year:
                return (one.year ?? .min) > (other.year ?? .min)
            case .recentlyAdded, .year, .name:
                let order = one.name.rawValue.localizedStandardCompare(other.name.rawValue)
                return order == .orderedSame ? one.id.rawValue < other.id.rawValue : order == .orderedAscending
            }
        }
    }

    /// The page that starts `skip` titles in, and whether another follows it.
    func page(from skip: Int) -> (titles: ArraySlice<SourceTitle>, hasMore: Bool) {
        let start = Swift.min(skip, count)
        let end = Swift.min(start + Self.pageSize, count)
        return (self[start..<end], end < count)
    }
}

/// A source's folders as its server arranges them, each holding its subfolders, then its titles
/// and episode files.
struct SourceFolders: Equatable, Sendable {
    /// A library or folder as a listing names it. A nil `parent` is the source's root.
    struct Folder: Equatable, Sendable {
        let id: SourceFolderID
        let name: Redacted<String>
        let parent: SourceFolderID?
    }

    private let entries: [SourceFolderID?: [SourceEntry]]

    /// Places each of `items` in its folder, in their order and once each. Folders holding no item,
    /// even below them, are left out, since they lead nowhere. Folders sort by name.
    init(folders: [Folder], items: [(entry: SourceEntry, folder: SourceFolderID?)]) {
        let parents = Dictionary(folders.compactMap { folder in folder.parent.map { (folder.id, $0) } }) { first, _ in first }
        var holding: Set<SourceFolderID> = []
        for item in items {
            var folder = item.folder
            while let id = folder, holding.insert(id).inserted {
                folder = parents[id]
            }
        }
        var entries: [SourceFolderID?: [SourceEntry]] = [nil: []]
        var seen: Set<SourceFolderID> = []
        let kept = folders
            .filter { holding.contains($0.id) && seen.insert($0.id).inserted }
            .sorted { $0.name.rawValue.localizedStandardCompare($1.name.rawValue) == .orderedAscending }
        for folder in kept {
            entries[folder.parent, default: []].append(.folder(folder.id, name: folder.name))
        }
        var placed: [SourceFolderID?: Set<SourceEntry>] = [:]
        for item in items where placed[item.folder, default: []].insert(item.entry).inserted {
            entries[item.folder, default: []].append(item.entry)
        }
        self.entries = entries
    }

    /// Nil when the source has no such folder.
    func entries(in folder: SourceFolderID?) -> [SourceEntry]? {
        entries[folder]
    }
}

/// A movie, show or video on a source, as its catalog lists it and, for a local id, its details.
struct SourceTitle: Equatable, Sendable {
    /// Stremio's poster of a title known by its IMDb id.
    static func cinemetaPoster(of id: MediaID) -> URL? {
        URL(string: "https://images.metahub.space/poster/medium/\(id.rawValue)/img")
    }

    enum Kind: Equatable, Sendable {
        case movie
        case series

        /// The add-on protocol's type.
        var name: String {
            contentType.rawValue
        }

        var contentType: ContentType {
            switch self {
            case .movie: .movie
            case .series: .series
            }
        }
    }

    /// Its IMDb id, so other add-ons know it too, or else its local id.
    let id: MediaID
    let kind: Kind
    let name: Redacted<String>
    /// The server's artwork, or for an IMDb id Stremio's.
    let poster: Redacted<URL>?
    let isLandscape: Bool
    let background: Redacted<URL>?
    let overview: Redacted<String>?
    let year: Int?
    /// When it came to the server: Jellyfin's creation date, or a WebDAV file's last change. A
    /// show's is its newest episode's.
    let added: Date?
    /// A show's episodes in order. Empty for a movie.
    let episodes: [SourceEpisode]
}

extension SourceTitle {
    /// As browsing shows it, opening its details.
    var preview: MetaPreview {
        MetaPreview(
            media: id, type: kind.contentType, name: name, poster: poster?.rawValue,
            posterShape: isLandscape ? .landscape : .poster, background: background?.rawValue, logo: nil,
            releaseInfo: year.map { Redacted(String($0)) }, description: overview
        )
    }
}

/// An episode of a show, which plays as `<show id>:<season>:<episode>`.
struct SourceEpisode: Equatable, Sendable {
    let season: Int
    let episode: Int
    let name: Redacted<String>
    let overview: Redacted<String>?
    let thumbnail: Redacted<URL>?
    /// When it first aired, as ISO 8601 text.
    let released: String?
}

/// A file of an item that the player can play, read when streams or subtitles are asked for.
struct SourceFile: Equatable, Sendable {
    let item: SourceItemID
    /// Which of the item's files: Jellyfin's media source id, or for WebDAV the item itself.
    let file: SourceItemID
    /// Its name on the server, without the folder.
    let name: Redacted<String>
    /// The video's resolution and codec, such as `720p H264 SDR`.
    let quality: String?
    let size: Int?
    let subtitles: [SourceSubtitle]
}

/// A subtitle file beside a video on the server.
struct SourceSubtitle: Equatable, Sendable {
    /// The server's number for it among the file's streams, or its place among WebDAV's sidecars.
    let index: Int
    /// ISO 639-2, such as `eng`.
    let language: String?
    let label: Redacted<String>
}
