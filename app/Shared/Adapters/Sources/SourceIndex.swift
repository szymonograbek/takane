import Foundation

/// A source server's own id for an item or one of its files, such as a Jellyfin item id. Letters
/// and digits only, so it is safe in a placeholder's path and inside a local id.
struct SourceItemID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init?(_ text: String) {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        rawValue = text
    }

    var description: String { rawValue }
}

/// What a source's add-on offers, read from a full listing of its libraries: the catalogs, the
/// metadata of the titles only it has, and which items play what.
struct SourceIndex: Equatable, Sendable {
    /// A library, which the add-on offers as one catalog.
    struct Library: Equatable, Sendable {
        let id: SourceItemID
        let name: Redacted<String>
        let type: SourceTitle.Kind
        /// Its movies, shows and videos, newest first.
        let titles: [SourceTitle]
    }

    let libraries: [Library]
    /// The items that play a movie or an episode, keyed by its IMDb id when the server knows it,
    /// else by its local id.
    let items: [PlayableID: [SourceItemID]]
    /// The titles found only on this source, by their local id.
    let localTitles: [MediaID: SourceTitle]
}

/// A movie, show or video on a source, as its catalog lists it and, for a local id, its details.
struct SourceTitle: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case movie
        case series

        /// The add-on protocol's type.
        var name: String {
            switch self {
            case .movie: "movie"
            case .series: "series"
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
    /// A show's episodes in order. Empty for a movie.
    let episodes: [SourceEpisode]
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
    /// Which of the item's files: Jellyfin's media source id.
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
    /// The server's number for it among the file's streams.
    let index: Int
    /// ISO 639-2, such as `eng`.
    let language: String?
    let label: Redacted<String>
}
