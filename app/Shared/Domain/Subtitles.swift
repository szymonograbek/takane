import Foundation

/// A subtitle file an add-on offers for the stream playing.
struct AddonSubtitle: Identifiable, Hashable, Sendable {
    struct ID: Hashable, Sendable {
        let addon: ManifestURL
        /// The add-on's own id for the file, which can say which title it is for.
        let key: Redacted<String>
    }

    let id: ID
    /// Configured add-ons may carry credentials in it.
    let url: Redacted<URL>
    /// As the add-on gives it, usually an ISO 639-2 code such as `eng`.
    let language: String
    /// The add-on's description of the file, such as its release name or how well it is timed.
    let label: Redacted<String>?
}

enum SubtitleSourceError: Error, Equatable, Sendable {
    case addonFailed(reason: String)
}

/// One add-on's answer for the stream playing.
struct SubtitleSource: Identifiable, Equatable, Sendable {
    let addon: ManifestURL
    let addonName: Redacted<String>
    let subtitles: Remote<[AddonSubtitle], SubtitleSourceError>

    var id: ManifestURL { addon }
}

/// Finds subtitle files for a stream across the user's add-ons.
protocol SubtitleService: Sendable {
    /// Every add-on's answer for `candidate`, playing from `source`, now and after every change.
    /// Call it after `PlaybackTracker.begin(candidate)`: providers may answer only for the
    /// candidate being tracked. Finishes once another candidate replaces it.
    func subtitles(for candidate: StreamCandidate, playing source: PlaybackSource) -> AsyncStream<[SubtitleSource]>
}
