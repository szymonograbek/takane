import Foundation

enum Fixture {
    static let manifest = ManifestURL("https://addon.example/manifest.json").require()
    static let otherManifest = ManifestURL("https://other.example/manifest.json").require()
    static let movie = PlayableID("tt0111161").require()
    static let episode = PlayableID("tt0944947:1:1").require()
    static let channel = PlayableID.liveChannel(MediaID("fox-sports").require())
    static let source = PlaybackSource(url: Redacted(URL(filePath: "/movie.mkv")), headers: ["Authorization": "token"])
    /// Release redaction under a fixed log key, so tests can assert the codes it writes.
    static let releaseKey = LogKey(bytes: Data(repeating: 7, count: LogKey.byteCount)).require()
    static let release = Redaction.pseudonymized(releaseKey.pseudonymizer)

    /// `body`'s text as a release log line reads it.
    static func inRelease<Value>(_ body: () -> Value) -> Value {
        Redaction.$current.withValue(release, operation: body)
    }

    static func candidate(_ playability: Playability = .playable(source), index: Int = 0, item: PlayableID = movie) -> StreamCandidate {
        StreamCandidate(
            id: StreamCandidate.ID(addon: manifest, index: index),
            item: item,
            name: Redacted("1080p"),
            description: nil,
            filename: Redacted("movie.mkv"),
            playability: playability,
            tracking: TrackingToken(payload: Redacted(.null))
        )
    }

    static func preferences(seekStep: SeekStep = .ten, upNext: UpNextBehavior = .defaults) -> Preferences {
        Preferences(languages: .streamDefaults, subtitleStyle: .defaults, seekStep: seekStep, hidesSpoilers: false, upNext: upNext)
    }
}

extension Fixture {
    static func preview(_ id: String, type: ContentType = .movie, background: URL? = nil) -> MetaPreview {
        MetaPreview(
            media: MediaID(id).require(), type: type, name: Redacted(id), poster: nil, posterShape: .poster,
            background: background, logo: nil, releaseInfo: nil, description: nil
        )
    }

    static func details(_ preview: MetaPreview, videos: [Video] = [], isWatched: Bool = false, isInLibrary: Bool = false) -> TitleDetails {
        TitleDetails(preview: preview, genres: [], runtime: nil, imdbRating: nil, videos: videos, isWatched: isWatched, isInLibrary: isInLibrary)
    }

    static func continueWatching(video: PlayableID, offset: Duration) -> ContinueWatchingItem {
        continueWatching(video: video, reason: .partway(offset: offset, duration: .seconds(3_000)))
    }

    static func continueWatching(video: PlayableID, reason: ContinueWatchingItem.Reason) -> ContinueWatchingItem {
        ContinueWatchingItem(media: video.media, type: .series, name: Redacted("Show"), poster: nil, background: nil, video: video, reason: reason)
    }
}

extension Optional {
    /// Unwraps a fixture that is valid by construction, failing loudly if it is not.
    func require(file: StaticString = #filePath, line: UInt = #line) -> Wrapped {
        guard let self else { fatalError("invalid fixture at \(file):\(line)") }
        return self
    }
}
