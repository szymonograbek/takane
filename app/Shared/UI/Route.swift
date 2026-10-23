import Foundation

/// Where a tab's navigation stack can go.
enum Route: Hashable, CustomStringConvertible {
    case details(MetaPreview)
    case streams(StreamsRequest)
    case genre(GenreFilter)
    /// Library with one of the user's sources picked, pushed from that source's row on Home.
    case library(SourceID)
    /// Settings › Sources, and one source's page. They are routes, not views pushed in place, so a
    /// source's folders, pushed as routes, show above them.
    case sourceSettings
    case source(SourceID)
    /// A folder of a source, and the name its screen shows.
    case sourceFolder(SourceBrowserFeature.Folder, name: Redacted<String>)

    /// Names the title or genre, not everything the screen is handed. Logs show it with the title's
    /// id redacted.
    var description: String {
        switch self {
        case .details(let preview): "details(\(preview.type)/\(preview.media))"
        case .streams(let request): "streams(\(request.video))"
        case .genre(let filter): "genre(\(filter.catalog.type)/\(filter.catalog.id), \(filter.genre))"
        case .library(let source): "library(\(source))"
        case .sourceSettings: "sourceSettings"
        case .source(let id): "source(\(id))"
        case .sourceFolder(let folder, _): "sourceFolder(\(folder))"
        }
    }
}

extension Route {
    /// A source's root: a Jellyfin server's libraries, or the top of a WebDAV folder.
    static func browsing(_ source: MediaSource) -> Route {
        .sourceFolder(SourceBrowserFeature.Folder(source: source.id, id: nil), name: source.name.text)
    }
}

/// What the streams screen looks up, and how it labels and resumes it.
struct StreamsRequest: Hashable, Identifiable {
    let video: PlayableID
    let title: Redacted<String>
    let backdrop: URL?

    var id: Self { self }
}
