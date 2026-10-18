import Foundation

/// A title as add-ons identify it, such as the IMDb id `tt0111161`.
struct MediaID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init?(_ rawValue: String) {
        guard !rawValue.isEmpty, !rawValue.contains(where: \.isWhitespace) else { return nil }
        self.rawValue = rawValue
    }

    var description: String { rawValue }
}

/// What streams are requested for. A series episode is never confused with the show it belongs to.
enum PlayableID: Hashable, Sendable, CustomStringConvertible {
    case movie(MediaID)
    case episode(MediaID, season: Int, episode: Int)

    /// Parses add-on ids: `tt0111161` as a movie, `tt0944947:1:1` (show, season, episode) as an episode.
    init?(_ text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            guard let media = MediaID(text) else { return nil }
            self = .movie(media)
        case 3:
            guard let media = MediaID(String(parts[0])), let season = Int(parts[1]), let episode = Int(parts[2]),
                  season >= 0, episode >= 0
            else { return nil }
            self = .episode(media, season: season, episode: episode)
        default:
            return nil
        }
    }

    /// The title this plays: the movie itself, or the show an episode belongs to.
    var media: MediaID {
        switch self {
        case .movie(let media), .episode(let media, _, _): media
        }
    }

    /// The add-on id, inverse of `init?(_:)`.
    var rawValue: String {
        switch self {
        case .movie(let media): media.rawValue
        case .episode(let media, let season, let episode): "\(media.rawValue):\(season):\(episode)"
        }
    }

    var description: String { rawValue }
}

/// An add-on's manifest URL. Add-ons are identified by it.
struct ManifestURL: Hashable, Sendable, CustomStringConvertible {
    let url: URL

    init?(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host() != nil else {
            return nil
        }
        self.url = url
    }

    init?(_ text: String) {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)) else { return nil }
        self.init(url)
    }

    var description: String { url.absoluteString }
}
