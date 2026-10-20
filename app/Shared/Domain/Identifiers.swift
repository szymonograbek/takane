import Foundation

/// A title as add-ons identify it, such as the IMDb id `tt0111161`. What someone watches is their
/// own business, so its text is redacted like a `Redacted` value's.
struct MediaID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init?(_ rawValue: String) {
        guard !rawValue.isEmpty, !rawValue.contains(where: \.isWhitespace) else { return nil }
        self.rawValue = rawValue
    }

    var description: String { Redaction.current.text(rawValue) }
}

/// What streams are requested for. A series episode is never confused with the show it belongs to.
/// Its pseudonymized text replaces the title with a code and keeps `episodeNumbers`: `#k3f9qa S1E1`.
enum PlayableID: Hashable, Sendable, CustomStringConvertible {
    case movie(MediaID)
    case episode(MediaID, season: Int, episode: Int)
    /// A live TV channel: its streams never end, so there is no progress to keep.
    case liveChannel(MediaID)

    /// Parses add-on ids, which do not say a channel is live: `tt0111161` as a movie, `tt0944947:1:1` (show, season, episode) as an episode.
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
        case .movie(let media), .episode(let media, _, _), .liveChannel(let media): media
        }
    }

    /// The add-on id, inverse of `init?(_:)`.
    var rawValue: String {
        switch self {
        case .movie(let media), .liveChannel(let media): media.rawValue
        case .episode(let media, let season, let episode): "\(media.rawValue):\(season):\(episode)"
        }
    }

    /// The season and episode that redacted text keeps, since alone they name nothing and they tell
    /// episodes of one show apart. Only an IMDb show's: other ids, such as kitsu's `kitsu:1376:1`,
    /// parse as episodes whose "season" is the title's number.
    var episodeNumbers: (season: Int, episode: Int)? {
        switch self {
        case .episode(let media, let season, let episode) where media.rawValue.hasPrefix("tt"): (season, episode)
        case .movie, .episode, .liveChannel: nil
        }
    }

    var description: String {
        switch (Redaction.current, episodeNumbers) {
        case (.revealed, _): rawValue
        case (.pseudonymized, let (season, episode)?): "\(media) S\(season)E\(episode)"
        case (.pseudonymized(let pseudonymizer), nil): pseudonymizer.code(rawValue)
        }
    }

    /// How the player names it: "Twin Peaks · S1 E3" for an episode of `title`, else `title`.
    func playerTitle(_ title: Redacted<String>) -> Redacted<String> {
        switch self {
        case .movie, .liveChannel: title
        case .episode(_, let season, let episode): Redacted("\(title.rawValue) · S\(season) E\(episode)")
        }
    }
}

/// An add-on's manifest URL. Add-ons are identified by it. Configured add-ons carry credentials,
/// such as a debrid key, in it.
struct ManifestURL: Hashable, Sendable, CustomStringConvertible {
    let url: Redacted<URL>

    init?(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host() != nil else {
            return nil
        }
        self.url = Redacted(url)
    }

    init?(_ text: String) {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)) else { return nil }
        self.init(url)
    }

    var description: String { url.description }
}
