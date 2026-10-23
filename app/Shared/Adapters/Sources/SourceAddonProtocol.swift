import Foundation

/// A request core makes of a source's add-on, parsed from its URL: `/<resource>/<type>/<id>.json`,
/// or with extras, `/<resource>/<type>/<id>/<name>=<value>&….json`.
enum SourceAddonRequest: Equatable, Sendable {
    case manifest
    /// A library's titles, or those whose name holds `search`.
    case catalog(SourceItemID, search: String?)
    case meta(MediaID)
    case streams(PlayableID)
    case subtitles(PlayableID)

    init?(_ url: InProcessURL) {
        let path = url.url.rawValue.path(percentEncoded: true).split(separator: "/").map(String.init)
        if path == ["manifest.json"] {
            self = .manifest
            return
        }
        guard path.count == 3 || path.count == 4, let last = path.last, last.hasSuffix(".json") else { return nil }
        var parts = path
        parts[parts.count - 1] = String(last.dropLast(".json".count))
        guard let id = parts[2].removingPercentEncoding else { return nil }
        let extra = parts.count == 4 ? Self.extra(parts[3]) : [:]
        switch parts[0] {
        case "catalog":
            guard let library = SourceItemID(id) else { return nil }
            self = .catalog(library, search: extra["search"])
        case "meta":
            guard let media = MediaID(id) else { return nil }
            self = .meta(media)
        case "stream":
            guard let playable = PlayableID(id) else { return nil }
            self = .streams(playable)
        case "subtitles":
            guard let playable = PlayableID(id) else { return nil }
            self = .subtitles(playable)
        default:
            return nil
        }
    }

    /// `search=big%20buck&skip=0` as names and values.
    private static func extra(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let field = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
            if field.count == 2 { values[field[0]] = field[1] }
        }
        return values
    }
}

/// What a placeholder URL that a source's add-on gives core stands for. Core only ever holds the
/// placeholder; the source's add-on turns it into the server's file when the player needs it.
enum SourcePlaceholder: Equatable, Sendable {
    /// `/play/<item>/<file>`
    case video(SourceItemID, file: SourceItemID)
    /// `/subtitle/<item>/<file>/<index>`
    case subtitle(SourceItemID, file: SourceItemID, index: Int)

    init?(_ url: InProcessURL) {
        let path = Array(url.url.rawValue.pathComponents.dropFirst())
        switch path.first {
        case "play":
            guard path.count == 3, let item = SourceItemID(path[1]), let file = SourceItemID(path[2]) else { return nil }
            self = .video(item, file: file)
        case "subtitle":
            guard path.count == 4, let item = SourceItemID(path[1]), let file = SourceItemID(path[2]), let index = Int(path[3]) else { return nil }
            self = .subtitle(item, file: file, index: index)
        default:
            return nil
        }
    }

    func url(on addon: SourceAddonDescriptor) -> URL {
        let root = addon.transportURL.deletingLastPathComponent()
        return switch self {
        case .video(let item, let file): root.appending(path: "play/\(item)/\(file)")
        case .subtitle(let item, let file, let index): root.appending(path: "subtitle/\(item)/\(file)/\(index)")
        }
    }
}

/// The add-on protocol's answers, in core's shapes, from a source's index and files. Their URLs are
/// placeholders and artwork, never a file on the server.
struct SourceAddonReplies {
    let addon: SourceAddonDescriptor

    func catalog(_ library: SourceIndex.Library, search: String?) -> CoreFetchReply {
        let titles = search.map { query in
            library.titles.filter { $0.name.rawValue.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        } ?? library.titles
        return Self.reply(["metas": titles.map(Preview.init)])
    }

    func meta(_ title: SourceTitle) -> CoreFetchReply {
        Self.reply(["meta": Meta(title)])
    }

    /// One stream per file, named after the source so the list says where it plays from.
    func streams(_ files: [SourceFile]) -> CoreFetchReply {
        Self.reply(["streams": files.map { file in
            StreamItem(
                url: SourcePlaceholder.video(file.item, file: file.file).url(on: addon).absoluteString,
                name: addon.name,
                description: [file.name.rawValue, file.quality, file.size.map { Int64($0).formatted(.byteCount(style: .file)) }]
                    .compactMap { $0 }.joined(separator: "\n"),
                behaviorHints: StreamItem.Hints(filename: file.name.rawValue, videoSize: file.size, bingeGroup: addon.localIDPrefix)
            )
        }])
    }

    func subtitles(_ files: [SourceFile]) -> CoreFetchReply {
        Self.reply(["subtitles": files.flatMap { file in
            file.subtitles.map { subtitle in
                SubtitleItem(
                    id: "\(addon.localIDPrefix)\(file.file)-\(subtitle.index)",
                    url: SourcePlaceholder.subtitle(file.item, file: file.file, index: subtitle.index).url(on: addon).absoluteString,
                    lang: subtitle.language ?? "und",
                    label: subtitle.label.rawValue
                )
            }
        }])
    }

    static let notFound = CoreFetchReply(status: 404, body: Data())

    private static func reply(_ body: some Encodable) -> CoreFetchReply {
        guard let data = try? JSONEncoder().encode(body) else { return CoreFetchReply(status: 500, body: Data()) }
        return CoreFetchReply(status: 200, body: data)
    }
}

/// core's `MetaItemPreview`.
private struct Preview: Encodable {
    let id: String
    let type: String
    let name: String
    let poster: URL?
    let posterShape: String
    let releaseInfo: String?

    init(_ title: SourceTitle) {
        id = title.id.rawValue
        type = title.kind.name
        name = title.name.rawValue
        poster = title.poster?.rawValue
        posterShape = title.isLandscape ? "landscape" : "poster"
        releaseInfo = title.year.map(String.init)
    }
}

/// core's `MetaItem`, with a show's episodes as its videos.
private struct Meta: Encodable {
    struct Video: Encodable {
        let id: String
        let title: String
        let season: Int
        let episode: Int
        let overview: String?
        let thumbnail: URL?
        let released: String?
    }

    let id: String
    let type: String
    let name: String
    let poster: URL?
    let posterShape: String
    let background: URL?
    let description: String?
    let releaseInfo: String?
    let videos: [Video]

    init(_ title: SourceTitle) {
        id = title.id.rawValue
        type = title.kind.name
        name = title.name.rawValue
        poster = title.poster?.rawValue
        posterShape = title.isLandscape ? "landscape" : "poster"
        background = title.background?.rawValue
        description = title.overview?.rawValue
        releaseInfo = title.year.map(String.init)
        videos = title.episodes.map { episode in
            Video(
                id: PlayableID.episode(title.id, season: episode.season, episode: episode.episode).rawValue,
                title: episode.name.rawValue, season: episode.season, episode: episode.episode,
                overview: episode.overview?.rawValue, thumbnail: episode.thumbnail?.rawValue, released: episode.released
            )
        }
    }
}

private struct StreamItem: Encodable {
    struct Hints: Encodable {
        let filename: String
        let videoSize: Int?
        /// Up next picks the next episode's stream from the same group.
        let bingeGroup: String
    }

    let url: String
    let name: String
    let description: String
    let behaviorHints: Hints
}

private struct SubtitleItem: Encodable {
    let id: String
    let url: String
    let lang: String
    let label: String
}
