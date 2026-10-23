import Foundation

/// A Kodi `.nfo` file in a WebDAV listing, as Radarr, Sonarr, tinyMediaManager and Jellyfin write
/// them beside videos, and the document it must hold to name its title: a `<movie>` for
/// `movie.nfo` and `<video>.nfo`, a `<tvshow>` for `tvshow.nfo`.
struct NfoFile: Hashable, Sendable {
    enum Root: String, Sendable {
        case movie
        case tvshow
    }

    let path: WebDAVPath
    let root: Root
    let size: Int?
    let modified: Date?
}

/// Reads the IMDb ids of a WebDAV source's `.nfo` files, a few at a time, each file at most
/// `sizeLimit`. What it read is kept by path, size and modification date, so listing the source
/// again reads only files that changed. A file that could not be read is read again on the next
/// listing; until then its title is named as if it had none.
actor NfoReader {
    static let sizeLimit = 256 << 10
    /// Reads at once, so a large library does not flood the server.
    private static let width = 4

    private struct Read {
        let size: Int?
        let modified: Date?
        let id: MediaID?
    }

    private var read: [WebDAVPath: Read] = [:]
    /// The reads under way, by path, each the batch that reads it.
    private var reading: [WebDAVPath: Task<Void, Never>] = [:]

    /// The ids `files` hold, by path, as far as they are read within `budget`. Reads still running
    /// then go on, and a later call finds what they read.
    func ids(of files: [NfoFile], in folder: WebDAVFolder, client: WebDAVClient, within budget: Duration) async -> [WebDAVPath: MediaID] {
        let small = files.filter { ($0.size ?? 0) <= Self.sizeLimit }
        let unread = small.filter { known(for: $0) == nil && reading[$0.path] == nil }
        if !unread.isEmpty {
            let batch = Task { await self.load(unread, in: folder, client: client) }
            for file in unread { reading[file.path] = batch }
        }
        await waitForAll(Set(small.compactMap { reading[$0.path] }), atMost: budget)
        return small.reduce(into: [:]) { ids, file in
            if let id = known(for: file)?.id { ids[file.path] = id }
        }
    }

    private func known(for file: NfoFile) -> Read? {
        guard let known = read[file.path], known.size == file.size, known.modified == file.modified else { return nil }
        return known
    }

    private func load(_ files: [NfoFile], in folder: WebDAVFolder, client: WebDAVClient) async {
        await withTaskGroup(of: (NfoFile, Data?).self) { group in
            var waiting = files[...]
            for file in waiting.prefix(Self.width) { group.addTask { await Self.body(of: file, in: folder, client: client) } }
            waiting = waiting.dropFirst(Self.width)
            for await (file, body) in group {
                if let body {
                    read[file.path] = Read(size: file.size, modified: file.modified, id: KodiNfo.imdbID(in: body, as: file.root))
                }
                reading[file.path] = nil
                if let next = waiting.popFirst() { group.addTask { await Self.body(of: next, in: folder, client: client) } }
            }
        }
    }

    private static func body(of file: NfoFile, in folder: WebDAVFolder, client: WebDAVClient) async -> (NfoFile, Data?) {
        do throws(SourceError) {
            return (file, try await client.read(file.path, in: folder, atMost: sizeLimit))
        } catch {
            Log.sources.warning("reading \(Redacted(file.path.names.joined(separator: "/"))) failed: \(error)")
            return (file, nil)
        }
    }
}

/// The IMDb id in a Kodi `.nfo` document: from the first of `<uniqueid type="imdb">`, `<imdbid>`
/// and `<id>` directly under its root that holds one. Its title and year are not read, so an
/// `.nfo` names a title only by id.
enum KodiNfo {
    /// Nil when `body` is not that kind of document or names no IMDb id. A document cut short, or
    /// followed by a link as Kodi allows, still gives the ids it holds before that.
    static func imdbID(in body: Data, as root: NfoFile.Root) -> MediaID? {
        let reader = NfoParser(root: root)
        let parser = XMLParser(data: body)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        _ = parser.parse()
        return reader.found
    }
}

private final class NfoParser: NSObject, XMLParserDelegate {
    /// In the order they are trusted.
    private enum Tag: Comparable {
        case uniqueID, imdbID, id
    }

    private let root: NfoFile.Root
    private var depth = 0
    private var current: Tag?
    private var text = ""
    private var ids: [Tag: MediaID] = [:]

    init(root: NfoFile.Root) {
        self.root = root
    }

    var found: MediaID? {
        ids.min { $0.key < $1.key }?.value
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]
    ) {
        depth += 1
        switch depth {
        case 1:
            if elementName != root.rawValue { parser.abortParsing() }
        case 2:
            text = ""
            current = switch elementName {
            case "uniqueid" where attributes["type"]?.lowercased() == "imdb": .uniqueID
            case "imdbid": .imdbID
            case "id": .id
            default: nil
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if current != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if depth == 2, let tag = current {
            if ids[tag] == nil, let id = MediaID.imdb(text.trimmingCharacters(in: .whitespacesAndNewlines)) { ids[tag] = id }
            current = nil
        }
        depth -= 1
    }
}
