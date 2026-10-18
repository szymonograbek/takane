import Foundation

enum Fixture {
    static let manifest = ManifestURL("https://addon.example/manifest.json").require()
    static let otherManifest = ManifestURL("https://other.example/manifest.json").require()
    static let movie = PlayableID("tt0111161").require()
    static let episode = PlayableID("tt0944947:1:1").require()
    static let source = PlaybackSource(url: URL(filePath: "/movie.mkv"), headers: ["Authorization": "token"])

    static func candidate(_ playability: Playability = .playable(source), index: Int = 0) -> StreamCandidate {
        StreamCandidate(
            id: StreamCandidate.ID(addon: manifest, index: index),
            item: movie,
            name: "1080p",
            description: nil,
            filename: "movie.mkv",
            playability: playability,
            tracking: TrackingToken(payload: .null)
        )
    }
}

extension Optional {
    /// Unwraps a fixture that is valid by construction, failing loudly if it is not.
    func require(file: StaticString = #filePath, line: UInt = #line) -> Wrapped {
        guard let self else { fatalError("invalid fixture at \(file):\(line)") }
        return self
    }
}
