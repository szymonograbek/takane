import SwiftUI

/// "Skip Intro", "Skip Recap", "Skip Credits" or "Skip Preview".
struct SkipButton: View {
    let segment: SkipSegment
    let skip: () -> Void

    var body: some View {
        Button(action: skip) {
            Label(segment.kind.skipTitle, systemImage: "forward.end.fill")
        }
        .accessibilityIdentifier("player.skip")
    }
}

/// The next episode's still and name, with buttons to play it now or turn it down.
struct UpNextCard: View {
    let next: UpNext
    var focus: FocusState<PlayerFocus?>.Binding
    let play: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Artwork(url: next.thumbnail, title: next.title.rawValue)
                .frame(width: Metrics.wideCardWidth, height: Metrics.wideCardWidth * 9 / 16)
                .clipShape(.rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Up Next").font(.caption).foregroundStyle(Palette.secondary)
                Text(episodeName).font(.headline).lineLimit(2)
            }
            .frame(width: Metrics.wideCardWidth, alignment: .leading)
            HStack {
                Button(action: play) {
                    Label(next.stream == nil ? "Choose Stream" : "Play Now", systemImage: "play.fill")
                }
                .focused(focus, equals: .playNext)
                .accessibilityIdentifier("player.upNext.play")
                Button("Cancel", action: dismiss)
                    .focused(focus, equals: .dismissNext)
                    .accessibilityIdentifier("player.upNext.dismiss")
            }
        }
        .padding(Metrics.playerPanelPadding)
        .background(Palette.canvas.opacity(0.85), in: .rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
        #if os(tvOS)
        .focusSection()
        #endif
    }

    /// "S1 E4 · The Big Day", or the episode number alone when it has no title.
    private var episodeName: String {
        let title = next.title.rawValue
        guard case .episode(_, let season, let episode) = next.video else { return title }
        let number = "S\(season) E\(episode)"
        return title.isEmpty ? number : "\(number) · \(title)"
    }
}

extension SegmentKind {
    var skipTitle: String {
        switch self {
        case .recap: "Skip Recap"
        case .intro: "Skip Intro"
        case .outro: "Skip Credits"
        case .preview: "Skip Preview"
        }
    }
}
