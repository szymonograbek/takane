import AetherEngine
import CoreGraphics
import Foundation

extension MediaTrack {
    /// `track` as listed by the engine, whose `id` is the container's stream index. `file` is the
    /// subtitle file it was added from, which the engine does not list.
    init(_ track: TrackInfo, kind: TrackKind, selected: Int?, file: URL?) {
        self.init(
            id: ID(kind: kind, number: track.id),
            title: Self.title(of: track),
            language: track.language,
            codec: track.codec.isEmpty ? nil : track.codec,
            channelCount: kind == .audio && track.channels > 0 ? track.channels : nil,
            isForced: track.isForced,
            externalFile: file,
            isSelected: track.id == selected
        )
    }

    /// The stream's own title. The engine names an untitled track after its language or number and
    /// its codec, which the track menu shows already.
    private static func title(of track: TrackInfo) -> String? {
        let generated = [track.language.map { "\($0.uppercased()) (\(track.codec))" }, "Track \(track.id) (\(track.codec))"]
        return track.name.isEmpty || generated.contains(track.name) ? nil : track.name
    }
}

extension SubtitleCue {
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
            text: run.text,
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
