import Foundation

/// Where a tab's navigation stack can go.
enum Route: Hashable, CustomStringConvertible {
    case details(MetaPreview)
    case streams(StreamsRequest)
    case genre(GenreFilter)

    /// Names the title or genre, not everything the screen is handed. Logs show it with the title's
    /// id redacted.
    var description: String {
        switch self {
        case .details(let preview): "details(\(preview.type)/\(preview.media))"
        case .streams(let request): "streams(\(request.video))"
        case .genre(let filter): "genre(\(filter.catalog.type)/\(filter.catalog.id), \(filter.genre))"
        }
    }
}

/// What the streams screen looks up, and how it labels and resumes it.
struct StreamsRequest: Hashable {
    let video: PlayableID
    let title: Redacted<String>
    let backdrop: URL?
}
