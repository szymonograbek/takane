import SwiftUI

/// The subtitles visible now, over the picture: text in `style`, bitmaps where the stream places
/// them. Text sits centered above the picture's bottom edge, or, when the style keeps file styling,
/// where its file places it. The second subtitles sit just above the text there, a step smaller and
/// in their own color. Text scales with the picture, so a small picture shows it exactly as a full
/// screen would.
struct SubtitleOverlay: View {
    let cues: [SubtitleCue]
    /// Text only; their file's placement is not kept.
    var secondCues: [SubtitleCue] = []
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
                ForEach(Array(textBlocks.enumerated()), id: \.offset) { _, block in
                    placed(block, on: picture)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// The text cues as drawn. A cue anchored at a point stands alone; the others join, in order,
    /// into one block per edge or corner they align to, so they stack instead of overlapping. The
    /// second subtitles join the block the player places.
    private var textBlocks: [TextBlock] {
        var blocks: [TextBlock] = []
        for case .text(let text) in cues {
            let placement = (style.usesFileStyling ? text.placement : nil) ?? Self.playerPlacement
            if placement.position == nil, let index = blocks.firstIndex(where: { $0.placement == placement }) {
                blocks[index].runs += Self.lineBreak + text.runs
            } else {
                blocks.append(TextBlock(placement: placement, runs: text.runs))
            }
        }
        let second = secondCues.compactMap { cue in if case .text(let text) = cue { text.runs } else { nil } }
        guard let first = second.first else { return blocks }
        let secondRuns = second.dropFirst().reduce(first) { $0 + Self.lineBreak + $1 }
        if let index = blocks.firstIndex(where: { $0.placement == Self.playerPlacement }) {
            blocks[index].secondRuns = secondRuns
        } else {
            blocks.append(TextBlock(placement: Self.playerPlacement, runs: [], secondRuns: secondRuns))
        }
        return blocks
    }

    private static let playerPlacement = SubtitlePlacement(alignment: .bottomCenter, position: nil)
    private static let lineBreak = [SubtitleRun(text: Redacted("\n"))]

    /// `block` at its position, or at its edge or corner inset by the style's offset: that fraction
    /// of the picture's height from the top or bottom, and of its width from the sides.
    @ViewBuilder
    private func placed(_ block: TextBlock, on picture: CGRect) -> some View {
        let alignment = block.placement.alignment
        let subtitle = VStack(alignment: alignment.frame.horizontal, spacing: 0) {
            if !block.secondRuns.isEmpty {
                StyledSubtitle(runs: block.secondRuns, line: .second, alignment: alignment, style: style, pictureHeight: picture.height)
            }
            if !block.runs.isEmpty {
                StyledSubtitle(runs: block.runs, line: .first, alignment: alignment, style: style, pictureHeight: picture.height)
            }
        }
        if let position = block.placement.position {
            // A zero-sized frame lines the text's anchor up with its single point.
            subtitle.fixedSize()
                .frame(width: 0, height: 0, alignment: alignment.frame)
                .position(x: picture.minX + position.x * picture.width, y: picture.minY + position.y * picture.height)
        } else {
            subtitle
                .padding(.vertical, style.bottomOffset.fraction * picture.height)
                .padding(.horizontal, style.bottomOffset.fraction * picture.width)
                .frame(width: picture.width, height: picture.height, alignment: alignment.frame)
                .position(x: picture.midX, y: picture.midY)
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

/// Text drawn as one block, the second subtitles above the first.
private struct TextBlock {
    let placement: SubtitlePlacement
    var runs: [SubtitleRun]
    var secondRuns: [SubtitleRun] = []
}

/// Subtitle text in a style, sized for a picture `pictureHeight` points tall. Runs keep their bold,
/// italic, underline and strikethrough; their colors and fonts only when the style keeps file
/// styling. The second subtitles are smaller and always in their own color.
private struct StyledSubtitle: View {
    /// Directions of the outline's copies, a unit step each.
    private static let outlineOffsets: [CGSize] = [
        CGSize(width: -1, height: -1), CGSize(width: 0, height: -1), CGSize(width: 1, height: -1),
        CGSize(width: -1, height: 0), CGSize(width: 1, height: 0),
        CGSize(width: -1, height: 1), CGSize(width: 0, height: 1), CGSize(width: 1, height: 1),
    ]

    let runs: [SubtitleRun]
    let line: PlayerFeature.SubtitleLine
    /// Lines are aligned to the same side as the block.
    let alignment: SubtitleAlignment
    let style: SubtitleStyle
    let pictureHeight: CGFloat

    var body: some View {
        let fontSize = pictureHeight * Metrics.subtitleTextHeight * style.size.fraction * (line == .second ? Metrics.secondSubtitleScale : 1)
        let padding = fontSize * Metrics.subtitlePadding
        ZStack {
            if style.outlineColor.isVisible {
                let width = fontSize * Metrics.subtitleOutline
                let outline = text(size: fontSize, color: { _ in Color(style.outlineColor) })
                ForEach(Self.outlineOffsets.indices, id: \.self) { index in
                    let offset = Self.outlineOffsets[index]
                    outline.offset(x: offset.width * width, y: offset.height * width)
                }
            }
            text(size: fontSize, color: textColor)
        }
        .multilineTextAlignment(alignment.text)
        .padding(.horizontal, padding)
        .padding(.vertical, padding / 3)
        .background(Color(style.backgroundColor), in: .rect(cornerRadius: padding / 3))
        .compositingGroup()
        .opacity(style.opacity.fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(runs.map(\.text.rawValue).joined())
        .accessibilityIdentifier(line == .first ? "player.subtitle" : "player.subtitle.second")
    }

    private func textColor(of run: SubtitleRun) -> Color {
        switch line {
        case .first: Color((style.usesFileStyling ? run.color : nil) ?? style.textColor)
        case .second: Palette.secondSubtitle
        }
    }

    /// The runs at `size` points, each in the color `color` gives it. The outline's copies share
    /// the fonts, so their glyphs line up with the text's.
    private func text(size: CGFloat, color: (SubtitleRun) -> Color) -> Text {
        var text = AttributedString()
        for run in runs {
            var part = AttributedString(run.text.rawValue)
            part.swiftUI.font = font(for: run, size: size)
            part.swiftUI.foregroundColor = color(run)
            part.swiftUI.underlineStyle = run.isUnderlined ? .single : nil
            part.swiftUI.strikethroughStyle = run.isStruckThrough ? .single : nil
            text += part
        }
        return Text(text)
    }

    private func font(for run: SubtitleRun, size: CGFloat) -> Font {
        let weight: Font.Weight = run.isBold || style.isBold ? .bold : .medium
        let font = if style.usesFileStyling, let name = run.fontName {
            Font.custom(name, size: size).weight(weight)
        } else {
            Font.system(size: size, weight: weight, design: style.font.design)
        }
        return run.isItalic ? font.italic() : font
    }
}

private extension SubtitleAlignment {
    var frame: Alignment {
        let horizontal: HorizontalAlignment = switch self.horizontal {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
        let vertical: VerticalAlignment = switch self.vertical {
        case .top: .top
        case .middle: .center
        case .bottom: .bottom
        }
        return Alignment(horizontal: horizontal, vertical: vertical)
    }

    var text: TextAlignment {
        switch horizontal {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
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
