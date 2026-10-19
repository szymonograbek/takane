import SwiftUI

extension View {
    /// The screen's main action, such as Play: filled in the brand red.
    func primaryActionStyle() -> some View {
        buttonStyle(.borderedProminent).tint(Palette.red)
    }

    /// The platform's style for artwork you select: tvOS lifts it under focus, macOS keeps it plain.
    func cardButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.card)
        #else
        buttonStyle(.plain)
        #endif
    }
}

/// A title's poster in a shelf or grid, named underneath. Selecting it opens the title. On tvOS
/// focus lifts the poster and moves its name out of the way; macOS keeps it plain.
struct PosterCard: View {
    let preview: MetaPreview

    var body: some View {
        NavigationLink(value: Route.details(preview)) {
            #if os(tvOS)
            // The borderless style stacks the poster over its name and lifts the label's first
            // `Image`, which `Artwork` is not, hence the highlight.
            poster.hoverEffect(.highlight)
            name
            #else
            VStack(alignment: .leading) {
                poster
                name
            }
            #endif
        }
        #if os(tvOS)
        .buttonStyle(.borderless)
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel(preview.name)
        .accessibilityIdentifier("poster.\(preview.media.rawValue)")
    }

    private var poster: some View {
        Artwork(url: preview.poster, title: preview.name)
            .aspectRatio(preview.posterShape.aspectRatio, contentMode: .fit)
            .clipShape(.rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .lockupFrame(.poster)
    }

    private var name: some View {
        Text(preview.name)
            .font(.caption)
            .foregroundStyle(Palette.secondary)
            .lineLimit(1)
            .lockupFrame(.poster)
    }
}

/// Blank posters holding a shelf's place while its catalog loads.
struct PosterPlaceholders: View {
    var body: some View {
        ForEach(0..<6, id: \.self) { _ in
            Palette.surface
                .aspectRatio(PosterShape.poster.aspectRatio, contentMode: .fit)
                .clipShape(.rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
                .lockupFrame(.poster)
        }
    }
}

/// A started title: wide artwork, how far in, and what is left. Selecting it picks a stream to resume.
struct ContinueCard: View {
    let item: ContinueWatchingItem
    let remove: () -> Void
    let markWatched: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.captionSpacing) {
            NavigationLink(value: item.route) {
                Artwork(url: item.background ?? item.poster, title: item.name)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(alignment: .bottom) {
                        if let fraction = item.fraction {
                            ProgressLine(fraction: fraction).padding(14)
                        }
                    }
                    .clipShape(.rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
            }
            .cardButtonStyle()
            .contextMenu {
                if item.canBeMarkedWatched {
                    Button("Mark as Watched", systemImage: "checkmark.circle", action: markWatched)
                }
                Button("Remove from Continue Watching", systemImage: "minus.circle", role: .destructive, action: remove)
            }
            .accessibilityLabel("\(item.name), \(item.caption)")
            .accessibilityIdentifier("continueWatching.item")
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.caption).bold().lineLimit(1)
                Text(item.caption).font(.caption2).foregroundStyle(Palette.secondary)
            }
        }
        .lockupFrame(.wide)
    }
}

/// A titled row of cards that scrolls sideways.
struct Shelf<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title3).bold()
                .padding(.horizontal, Metrics.screenPadding)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Metrics.shelfSpacing) {
                    content()
                }
            }
            // As safe area rather than padding, so `lockupFrame` divides only the width between the margins.
            .safeAreaPadding(.horizontal, Metrics.screenPadding)
            .scrollIndicators(.hidden)
            // Focused cards grow past the row's bounds.
            .scrollClipDisabled()
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }
}

extension View {
    /// Sizes a lockup to one column of the shelf it sits in.
    func lockupFrame(_ lockup: Lockup) -> some View {
        containerRelativeFrame(.horizontal, count: lockup.columns, spacing: Metrics.shelfSpacing, alignment: .leading)
    }
}

extension PosterShape {
    /// Width over height.
    var aspectRatio: CGFloat {
        switch self {
        case .poster: 2.0 / 3.0
        case .landscape: 16.0 / 9.0
        case .square: 1
        }
    }
}

extension ContinueWatchingItem {
    /// How much of `video` was watched, for a title stopped partway.
    var fraction: Double? {
        guard case .partway(let offset, let duration) = reason else { return nil }
        return duration > .zero ? offset / duration : 0
    }

    /// "S2 · E4 · 23 min left", "1 h 12 min left" for a movie, or "New episode".
    var caption: String {
        switch reason {
        case .partway(let offset, let duration):
            let left = Duration.timeLeftFormat(duration - offset)
            guard case .episode(_, let season, let episode) = video else { return left }
            return "S\(season) · E\(episode) · \(left)"
        case .newEpisodes(let count):
            return count == 1 ? "New episode" : "\(count) new episodes"
        }
    }
}

extension Duration {
    /// "23 min left", "1 h 12 min left".
    static func timeLeftFormat(_ remaining: Duration) -> String {
        let minutes = max(1, Int(remaining.components.seconds) / 60)
        return minutes < 60 ? "\(minutes) min left" : "\(minutes / 60) h \(minutes % 60) min left"
    }

    /// "1:02:05" or "4:05".
    var clock: String {
        let total = max(0, Int(components.seconds))
        return total >= 3_600
            ? String(format: "%d:%02d:%02d", total / 3_600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
