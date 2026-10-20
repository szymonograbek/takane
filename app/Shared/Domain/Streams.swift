import Foundation

/// Where and how a player fetches a stream.
struct PlaybackSource: Hashable, Sendable {
    /// Debrid links carry the user's key.
    let url: Redacted<URL>
    /// Sent with every HTTP request for the stream.
    let headers: [String: String]
}

enum Playability: Hashable, Sendable {
    case playable(PlaybackSource)
    /// Torrent, archive, YouTube, external link and similar; `kind` names it for display.
    case unsupported(kind: String)
}

/// Opaque data the stream provider needs back to track playback of a candidate it returned.
/// Only the provider that created it reads `payload`.
struct TrackingToken: Hashable, Sendable {
    /// Core's holds the stream as its add-on gave it, name included.
    let payload: Redacted<JSONValue>
}

/// One stream an add-on offers for an item.
struct StreamCandidate: Identifiable, Hashable, Sendable {
    struct ID: Hashable, Sendable {
        let addon: ManifestURL
        let index: Int
    }

    let id: ID
    let item: PlayableID
    /// Add-ons put their own name, or the name of the add-on they wrap, in these.
    let name: Redacted<String>?
    let description: Redacted<String>?
    let filename: Redacted<String>?
    let playability: Playability
    let tracking: TrackingToken

    var source: PlaybackSource? {
        if case .playable(let source) = playability { source } else { nil }
    }
}

enum StreamSourceError: Error, Equatable, Sendable {
    case addonFailed(reason: String)
}

/// One add-on's answer for an item.
struct StreamSource: Identifiable, Equatable, Sendable {
    let addon: ManifestURL
    let addonName: Redacted<String>
    let candidates: Remote<[StreamCandidate], StreamSourceError>

    var id: ManifestURL { addon }
}

/// Every add-on's answer for an item so far.
struct StreamResults: Equatable, Sendable {
    let item: PlayableID
    let sources: [StreamSource]
    /// Every source has answered and playback can be tracked.
    let isComplete: Bool
}

/// Finds streams for items across the user's add-ons.
protocol StreamService: Sendable {
    /// Results now, then after every change. Finishes once complete, or when a newer
    /// `streams(for:)` call replaces this one: providers may serve one lookup at a time.
    /// A failing add-on is a failed source inside the results, never a failed lookup.
    func streams(for item: PlayableID) -> AsyncStream<StreamResults>
}
