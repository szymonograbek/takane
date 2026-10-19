import SwiftUI

/// The subtitles visible now, over the picture: text centered above its bottom edge in `style`,
/// bitmaps where the stream places them. Text scales with the picture, so a small picture shows
/// it exactly as a full screen would.
struct SubtitleOverlay: View {
    let cues: [SubtitleCue]
    /// Nil until the engine knows it; the picture then fills the screen.
    let videoSize: VideoSize?
    let style: SubtitleStyle

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
                    StyledSubtitle(text: lines.joined(separator: "\n"), style: style, pictureHeight: picture.height)
                        .padding(.bottom, style.bottomOffset.fraction * picture.height)
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

/// Subtitle text in a style, sized for a picture `pictureHeight` points tall.
private struct StyledSubtitle: View {
    /// Directions of the outline's copies, a unit step each.
    private static let outlineOffsets: [CGSize] = [
        CGSize(width: -1, height: -1), CGSize(width: 0, height: -1), CGSize(width: 1, height: -1),
        CGSize(width: -1, height: 0), CGSize(width: 1, height: 0),
        CGSize(width: -1, height: 1), CGSize(width: 0, height: 1), CGSize(width: 1, height: 1),
    ]

    let text: String
    let style: SubtitleStyle
    let pictureHeight: CGFloat

    var body: some View {
        let fontSize = pictureHeight * Metrics.subtitleTextHeight * style.size.fraction
        let padding = fontSize * Metrics.subtitlePadding
        ZStack {
            if style.outlineColor.isVisible {
                let width = fontSize * Metrics.subtitleOutline
                ForEach(Self.outlineOffsets.indices, id: \.self) { index in
                    let offset = Self.outlineOffsets[index]
                    Text(text).foregroundStyle(Color(style.outlineColor))
                        .offset(x: offset.width * width, y: offset.height * width)
                }
            }
            Text(text).foregroundStyle(Color(style.textColor))
        }
        .font(.system(size: fontSize, weight: style.isBold ? .bold : .medium, design: style.font.design))
        .multilineTextAlignment(.center)
        .padding(.horizontal, padding)
        .padding(.vertical, padding / 3)
        .background(Color(style.backgroundColor), in: .rect(cornerRadius: padding / 3))
        .compositingGroup()
        .opacity(style.opacity.fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityIdentifier("player.subtitle")
    }
}

private extension SubtitleFont {
    var design: Font.Design {
        switch self {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
}

extension Color {
    init(_ color: SubtitleColor) {
        self.init(
            .sRGB,
            red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255,
            opacity: Double(color.alpha) / 255
        )
    }
}
