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

/// A title's poster in a shelf or grid, named underneath. Selecting it opens the title.
struct PosterCard: View {
    let preview: MetaPreview

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.captionSpacing) {
            NavigationLink(value: Route.details(preview)) {
                Artwork(url: preview.poster, title: preview.name)
                    .frame(width: Metrics.posterWidth, height: Metrics.posterWidth * preview.posterShape.heightRatio)
                    .clipShape(.rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
            }
            .cardButtonStyle()
            .accessibilityLabel(preview.name)
            .accessibilityIdentifier("poster.\(preview.media.rawValue)")
            Text(preview.name)
                .font(.caption)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                .frame(width: Metrics.posterWidth, alignment: .leading)
        }
    }
}

/// Blank posters holding a shelf's place while its catalog loads.
struct PosterPlaceholders: View {
    var body: some View {
        ForEach(0..<6, id: \.self) { _ in
            Palette.surface
                .frame(width: Metrics.posterWidth, height: Metrics.posterWidth * PosterShape.poster.heightRatio)
                .clipShape(.rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
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
            NavigationLink(value: Route.streams(item.streamsRequest)) {
                Artwork(url: item.background ?? item.poster, title: item.name)
                    .frame(width: Metrics.wideCardWidth, height: Metrics.wideCardWidth * 9 / 16)
                    .overlay(alignment: .bottom) {
                        ProgressLine(fraction: item.fraction).padding(14)
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
            .accessibilityLabel("\(item.name), \(item.remainingLabel)")
            .accessibilityIdentifier("continueWatching.item")
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.caption).bold().lineLimit(1)
                Text(item.remainingLabel).font(.caption2).foregroundStyle(Palette.secondary)
            }
            .frame(width: Metrics.wideCardWidth, alignment: .leading)
        }
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
                .padding(.horizontal, Metrics.screenPadding)
            }
            .scrollIndicators(.hidden)
            // Focused cards grow past the row's bounds.
            .scrollClipDisabled()
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }
}

extension PosterShape {
    var heightRatio: CGFloat {
        switch self {
        case .poster: 1.5
        case .landscape: 9.0 / 16.0
        case .square: 1
        }
    }
}

extension ContinueWatchingItem {
    var fraction: Double {
        duration > .zero ? offset / duration : 0
    }

    /// "S2 · E4 · 23 min left", or "1 h 12 min left" for a movie.
    var remainingLabel: String {
        let left = Duration.timeLeftFormat(duration - offset)
        guard case .episode(_, let season, let episode) = video else { return left }
        return "S\(season) · E\(episode) · \(left)"
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
