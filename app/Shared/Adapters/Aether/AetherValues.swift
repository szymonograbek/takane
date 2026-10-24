import AetherEngine
import CoreGraphics
import Foundation

extension MediaTrack {
    /// `track` as listed by the engine, whose `id` is the container's stream index. `file` is the
    /// subtitle file it was added from, which the engine does not list.
    init(_ track: TrackInfo, kind: TrackKind, selected: Int?, file: Redacted<URL>?) {
        self.init(
            id: ID(kind: kind, number: track.id),
            title: Self.title(of: track).map(Redacted.init),
            language: track.language,
            codec: track.codec.isEmpty ? nil : track.codec,
            channelCount: kind == .audio && track.channels > 0 ? track.channels : nil,
            isForced: track.isForced,
            externalFile: file,
            isSelected: track.id == selected,
            isImageBased: kind == .subtitle && Self.imageCodecs.contains { track.codec.lowercased().contains($0) }
        )
    }

    /// Picture subtitle codecs by part of their name, as the engine's own `isBitmapSubtitleCodec`,
    /// which is not public, tells them apart.
    private static let imageCodecs = ["pgs", "hdmv", "dvb_sub", "dvbsub", "dvd_sub", "dvdsub", "vobsub", "xsub"]

    /// The stream's own title. The engine names an untitled track after its language or number and
    /// its codec, which the track menu shows already.
    private static func title(of track: TrackInfo) -> String? {
        let generated = [track.language.map { "\($0.uppercased()) (\(track.codec))" }, "Track \(track.id) (\(track.codec))"]
        return track.name.isEmpty || generated.contains(track.name) ? nil : track.name
    }
}

extension SubtitleCue {
    /// `cue` as drawn on a video of `video`'s shape.
    init(_ cue: AetherEngine::SubtitleCue, on video: VideoSize?) {
        switch cue.body {
        case .image(let image): self.init(image, on: video)
        case .text(let plain): self = .text(SubtitleText(runs: [SubtitleTextRun(text: plain, color: nil)], placement: cue.placement))
        case .richText(let runs): self = .text(SubtitleText(runs: runs, placement: cue.placement))
        }
    }

    /// `image` placed on a video of `video`'s shape. The engine places a bitmap on its subtitle
    /// canvas, which a cropped rip can make taller than the video, so the canvas is fitted to the
    /// video's width and centered on it.
    init(_ image: SubtitleImage, on video: VideoSize?) {
        var frame = image.position
        if let video, image.canvasSize.width > 0, image.canvasSize.height > 0 {
            // The canvas's height as a share of the video's, once both are as wide.
            let share = (image.canvasSize.height / image.canvasSize.width) / (CGFloat(video.height) / CGFloat(video.width))
            frame.origin.y = (1 - share) / 2 + frame.origin.y * share
            frame.size.height *= share
        }
        self = .image(image.cgImage, frame: frame)
    }
}

extension TimedCue {
    /// A cue the engine leaves open lasts at least this long, in seconds: it shows until the next
    /// replaces it. The engine's own threshold, `subtitleOpenEndedWindowSeconds`, is not public.
    private static let openEnded = 3_600.0
    /// How long an open cue is drawn while no cue follows it yet, in seconds.
    private static let unclosedLength = 10.0

    /// An engine cue, `start` to `end` in source seconds, moved onto the position's axis by
    /// `clock`; `text` is nil for a bitmap. An open cue ends at the next of `starts`, every cue's
    /// start in order, and at most `unclosedLength` after its own.
    init(number: Int, start: Double, end: Double, text: String?, starts: [Double], clock: SourceClock) {
        let line = text?.split(separator: "\n", omittingEmptySubsequences: true).first ?? ""
        let closed = end - start < Self.openEnded ? end : min(starts.first { $0 > start } ?? .infinity, start + Self.unclosedLength)
        self.init(
            id: ID(number: number),
            range: clock.position(ofSource: start) ..< clock.position(ofSource: max(start, closed)),
            text: Redacted(line.trimmingCharacters(in: .whitespaces))
        )
    }
}

extension Chapter {
    /// `chapter` as the engine lists it, whose `id` is its place in order from zero. Release files
    /// often title chapters with their start time ("00:21:04.000"), which names nothing, so those
    /// get the engine's own name for an untitled chapter.
    init(_ chapter: ChapterInfo) {
        let isTime = chapter.name.allSatisfy { $0.isNumber || $0 == ":" || $0 == "." }
        let title = isTime ? "Chapter \(chapter.id + 1)" : chapter.name
        self.init(id: ID(number: chapter.id), title: Redacted(title), start: .seconds(chapter.startSeconds))
    }
}

extension SubtitleText {
    /// The runs of a text cue, placed where the cue asks.
    init(runs: [SubtitleTextRun], placement: SubtitleTextPlacement?) {
        self.init(runs: runs.map(SubtitleRun.init), placement: placement.flatMap(SubtitlePlacement.init))
    }
}

extension SubtitleRun {
    /// `run` without its size, which is in the script's own units.
    init(_ run: SubtitleTextRun) {
        self.init(
            text: Redacted(run.text),
            isBold: run.isBold,
            isItalic: run.isItalic,
            isUnderlined: run.isUnderlined,
            isStruckThrough: run.isStruckThrough,
            color: run.color.map { SubtitleColor(red: $0.r, green: $0.g, blue: $0.b) },
            fontName: run.fontName
        )
    }
}

extension SubtitlePlacement {
    /// Nil when `placement` sets neither a known alignment nor a position. A position alone aligns
    /// the text's bottom center to it, as ASS does by default.
    init?(_ placement: SubtitleTextPlacement) {
        let alignment = placement.alignment.flatMap(SubtitleAlignment.init(numpad:))
        guard alignment != nil || placement.position != nil else { return nil }
        self.init(alignment: alignment ?? .bottomCenter, position: placement.position)
    }
}

extension AetherEngine::SubtitleCue {
    /// Whether the cue is on screen at `time`, in source seconds.
    func isShown(at time: Double) -> Bool {
        startTime <= time && time < endTime
    }
}
