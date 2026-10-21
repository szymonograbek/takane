import Foundation

// The player model's state, apart from `CoreWire.swift` to keep both files short.

struct PlayerState: Decodable, Sendable {
    /// What `CoreAction.Load.player` loaded, as core echoes it back.
    struct Selected: Decodable, Sendable {
        let stream: Stream
        let streamRequest: ResourceRequest?
        let metaRequest: ResourceRequest?
        let subtitlesPath: ResourcePath?
    }

    /// The fields of core's `MetaItem` the up next offer shows.
    struct Show: Decodable, Sendable {
        let name: String
        let background: String?
    }

    let selected: Selected?
    let subtitles: [ResourceLoadable<[Subtitles]>]
    let metaItem: ResourceLoadable<Show>?
    /// The episode after the selected one, once `metaItem` is ready.
    let nextVideo: MetaDetailsState.Video?
    /// The next video's streams from the selected stream's add-on.
    let nextStreams: ResourceLoadable<[Stream]>?
    /// The first of `nextStreams` in the selected stream's binge group.
    let nextStream: Stream?
    /// What was saved for the selected video, or carried over from an earlier one of the same title.
    let streamState: StreamItemState?
    /// Stremio's skip times for the selected episode, which core asks for by itself for Stremio
    /// Premium accounts.
    let introOutro: IntroOutro?

    /// Whether core has `candidate`, playing from `source`, selected.
    func plays(_ candidate: StreamCandidate, from source: PlaybackSource) -> Bool {
        guard let selected else { return false }
        return selected.stream.source == .url(source.url.rawValue) && selected.subtitlesPath?.id == candidate.item.rawValue
    }
}

/// core's `IntroOutro`, in milliseconds, fitted by core to the duration the player reported.
struct IntroOutro: Decodable, Equatable, Sendable {
    struct Intro: Decodable, Equatable, Sendable {
        let from: UInt64
        let to: UInt64
        /// The intro's length on another cut, set when that cut's length differs from this stream's
        /// and core scaled the times to it.
        let duration: UInt64?
    }

    let intro: Intro?
    /// Where the credits start.
    let outro: UInt64?
}

extension PlayerState {
    /// Stremio's skip times once core holds them for `item`, nil before. Core gives no confidence;
    /// the player does not weigh it, so the segments carry 1.
    func skipSegments(for item: PlayableID, within stream: ClosedRange<Duration>) -> SkipSegments? {
        guard let introOutro, selected?.streamRequest?.path.id == item.rawValue else { return nil }
        let intro = introOutro.intro.flatMap { intro in
            // An intro scaled from another cut is a guess at this one's.
            SkipSegment(
                kind: .intro, start: .milliseconds(intro.from), end: .milliseconds(intro.to), within: stream,
                fit: intro.duration == nil ? .matched : .unknown, confidence: 1
            )
        }
        // Core keeps the credits as far from the end as on the cut they were taken on.
        let outro = introOutro.outro.flatMap { start in
            SkipSegment(kind: .outro, start: .milliseconds(start), end: stream.upperBound, within: stream, fit: .matched, confidence: 1)
        }
        let found = [intro, outro].compactMap(\.self).sorted { $0.range.lowerBound < $1.range.lowerBound }
        return SkipSegments(item: item, segments: found, introLengthEstimate: nil)
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
