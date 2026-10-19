import SwiftUI

/// The subtitles visible now, over the picture: text centered above its bottom edge, bitmaps where
/// the stream places them.
struct SubtitleOverlay: View {
    let cues: [SubtitleCue]
    /// Nil until the engine knows it; the picture then fills the screen.
    let videoSize: VideoSize?

    var body: some View {
        GeometryReader { geometry in
            let picture = Self.picture(of: videoSize, in: geometry.size)
            ZStack {
                ForEach(Array(cues.enumerated()), id: \.offset) { _, cue in
                    if case .image(let image, let frame) = cue {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: frame.width * picture.width, height: frame.height * picture.height)
                            .position(x: picture.minX + frame.midX * picture.width, y: picture.minY + frame.midY * picture.height)
                    }
                }
                if !lines.isEmpty {
                    Text(lines.joined(separator: "\n"))
                        .font(.system(Metrics.subtitleStyle, weight: .semibold))
                        .foregroundStyle(Palette.subtitle)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Metrics.subtitlePadding)
                        .padding(.vertical, Metrics.subtitlePadding / 3)
                        .background(Palette.subtitleBacking, in: .rect(cornerRadius: Metrics.cornerRadius / 2))
                        .accessibilityIdentifier("player.subtitle")
                        .padding(.bottom, Metrics.subtitleInset)
                        .frame(width: picture.width, height: picture.height, alignment: .bottom)
                        .position(x: picture.midX, y: picture.midY)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var lines: [String] {
        cues.compactMap { cue in
            if case .text(let text) = cue { text } else { nil }
        }
    }

    /// Where the picture sits in `bounds`: fitted whole and centered, as the video layer draws it.
    private static func picture(of video: VideoSize?, in bounds: CGSize) -> CGRect {
        guard let video else { return CGRect(origin: .zero, size: bounds) }
        let scale = min(bounds.width / CGFloat(video.width), bounds.height / CGFloat(video.height))
        let size = CGSize(width: CGFloat(video.width) * scale, height: CGFloat(video.height) * scale)
        return CGRect(origin: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), size: size)
    }
}
