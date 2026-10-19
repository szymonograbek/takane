import Foundation

// The player model's state, apart from `CoreWire.swift` to keep both files short.

struct PlayerState: Decodable, Sendable {
    /// What `CoreAction.Load.player` loaded, as core echoes it back.
    struct Selected: Decodable, Sendable {
        let stream: Stream
        let subtitlesPath: ResourcePath?
    }

    let selected: Selected?
    let subtitles: [ResourceLoadable<[Subtitles]>]
    /// What was saved for the selected video, or carried over from an earlier one of the same title.
    let streamState: StreamItemState?

    /// Whether core has `candidate`, playing from `source`, selected.
    func plays(_ candidate: StreamCandidate, from source: PlaybackSource) -> Bool {
        guard let selected else { return false }
        return selected.stream.source == .url(source.url) && selected.subtitlesPath?.id == candidate.item.rawValue
    }
}

/// core's `StreamItemState`: what the viewer changed from the defaults for one video. The app manages
/// the track and speed keys and sends the others back as core gave them, since core replaces the
/// whole state on `StreamStateChanged`.
struct StreamItemState: Codable, Equatable, Sendable {
    struct SubtitleTrack: Codable, Equatable, Sendable {
        /// The engine's track number for an embedded track, the file's URL for an add-on's.
        let id: String
        let embedded: Bool
        let language: String?
    }

    struct AudioTrack: Codable, Equatable, Sendable {
        let id: String
        let language: String?
    }

    var subtitleTrack: SubtitleTrack?
    var audioTrack: AudioTrack?
    var playbackSpeed: Double?
    /// Keys the app does not manage, such as delays and the subtitle size.
    var others: [String: JSONValue] = [:]

    private enum CodingKeys: String, CodingKey { case subtitleTrack, audioTrack, playbackSpeed }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subtitleTrack = try container.decodeIfPresent(SubtitleTrack.self, forKey: .subtitleTrack)
        audioTrack = try container.decodeIfPresent(AudioTrack.self, forKey: .audioTrack)
        playbackSpeed = try container.decodeIfPresent(Double.self, forKey: .playbackSpeed)
        others = try [String: JSONValue](from: decoder).filter { key, _ in CodingKeys(stringValue: key) == nil }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for (key, value) in others {
            try container.encode(value, forKey: DynamicKey(key))
        }
        try container.encodeIfPresent(subtitleTrack, forKey: DynamicKey(CodingKeys.subtitleTrack.stringValue))
        try container.encodeIfPresent(audioTrack, forKey: DynamicKey(CodingKeys.audioTrack.stringValue))
        try container.encodeIfPresent(playbackSpeed, forKey: DynamicKey(CodingKeys.playbackSpeed.stringValue))
    }
}

/// core's `Subtitles`, one file an add-on offers.
struct Subtitles: Decodable, Sendable {
    let id: String
    let lang: String
    /// Decoded as text so one malformed URL drops that file instead of the add-on's list.
    let url: String
    let label: String?
}
