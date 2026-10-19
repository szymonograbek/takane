import Foundation

// What core actions ask for: add-on resources and catalog selections, in core's JSON shapes.

struct ResourcePath: Codable, Hashable, Sendable {
    var resource: String
    var type: String
    var id: String
    var extra: [[String]] = []

    static func meta(type: String, id: String) -> ResourcePath {
        ResourcePath(resource: "meta", type: type, id: id)
    }

    static func stream(type: String, id: String) -> ResourcePath {
        ResourcePath(resource: "stream", type: type, id: id)
    }

    static func subtitles(type: String, id: String) -> ResourcePath {
        ResourcePath(resource: "subtitles", type: type, id: id)
    }

    static func catalog(type: String, id: String, extra: [[String]]) -> ResourcePath {
        ResourcePath(resource: "catalog", type: type, id: id, extra: extra)
    }
}

/// core's `catalogs_with_extra::Selected`: which catalogs a `CatalogsWithExtra` model loads.
struct CatalogsSelection: Codable, Equatable, Sendable {
    /// Every type when nil.
    var type: String?
    /// `[name, value]` pairs, such as `["search", "shawshank"]`.
    var extra: [[String]]

    /// Every catalog without a required extra.
    static let board = CatalogsSelection(type: nil, extra: [])

    /// Every catalog that supports the `search` extra, asked for `text`.
    static func search(_ text: SearchText) -> CatalogsSelection {
        CatalogsSelection(type: nil, extra: [["search", text.rawValue]])
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // core expects an explicit null for every type.
        try container.encode(type, forKey: .type)
        try container.encode(extra, forKey: .extra)
    }

    private enum CodingKeys: String, CodingKey { case type, extra }
}

/// core's `LibraryRequest`, without the page: a load asks for the first, `LoadNextPage` for more.
struct LibraryRequest: Codable, Equatable, Sendable {
    /// Every type when nil.
    var type: String?
    /// core's `Sort`, such as `lastwatched`.
    var sort: String

    init(_ filter: LibraryFilter) {
        type = filter.type?.rawValue
        sort = switch filter.sort {
        case .recentlyWatched: "lastwatched"
        case .name: "name"
        case .unwatchedFirst: "notwatched"
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // core expects an explicit null for every type.
        try container.encode(type, forKey: .type)
        try container.encode(sort, forKey: .sort)
    }

    private enum CodingKeys: String, CodingKey { case type, sort }
}

struct ResourceRequest: Codable, Hashable, Sendable {
    var base: URL
    var path: ResourcePath
}

extension ResourcePath {
    var json: JSONValue {
        .object([
            "resource": .string(resource),
            "type": .string(type),
            "id": .string(id),
            "extra": .array(extra.map { .array($0.map(JSONValue.string)) }),
        ])
    }
}

extension ResourceRequest {
    var json: JSONValue {
        .object(["base": .string(base.absoluteString), "path": path.json])
    }
}
