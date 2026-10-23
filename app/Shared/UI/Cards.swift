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
        PosterLockup(route: .details(preview), name: preview.name.rawValue) {
            Artwork(url: preview.poster, title: preview.name.rawValue)
                .aspectRatio(preview.posterShape.aspectRatio, contentMode: .fit)
        }
        .accessibilityLabel(preview.name.rawValue)
        .accessibilityIdentifier("poster.\(preview.media.rawValue)")
    }
}

/// The last lockup of a source's row on Home, poster-sized like the row's: it opens Library with
/// the source picked, pushed in this tab, so Menu comes back to the row.
struct SeeAllCard: View {
    let source: SourceID

    var body: some View {
        PosterLockup(route: .library(source), name: "See All") {
            Palette.surface
                .aspectRatio(PosterShape.poster.aspectRatio, contentMode: .fit)
                .overlay {
                    Image(systemName: "square.grid.2x2").font(.largeTitle).foregroundStyle(Palette.secondary)
                }
        }
        .accessibilityIdentifier("shelf.seeAll")
    }
}

/// A poster-sized lockup named underneath, opening `route`.
private struct PosterLockup<Art: View>: View {
    let route: Route
    let name: String
    @ViewBuilder let art: () -> Art

    var body: some View {
        NavigationLink(value: route) {
            #if os(tvOS)
            // The borderless style stacks the poster over its name and lifts the label's first
            // `Image`, which the artwork is not, hence the highlight.
            poster.hoverEffect(.highlight)
            caption
            #else
            VStack(alignment: .leading) {
                poster
                caption
            }
            #endif
        }
        #if os(tvOS)
        .buttonStyle(.borderless)
        #else
        .buttonStyle(.plain)
        #endif
    }

    private var poster: some View {
        art()
            .clipShape(.rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .lockupFrame(.poster)
    }

    private var caption: some View {
        Text(name)
            .font(.caption)
            .foregroundStyle(Palette.secondary)
            .labelLineLimit()
            .lockupFrame(.poster)
    }
}

/// Titles in rows of posters between the screen's margins, scrolling down. `card` draws each title,
/// usually as a `PosterCard`.
struct PosterGrid<Card: View>: View {
    /// The screen's title, above the first row and scrolling with the grid.
    var title: String?
    let titles: [MetaPreview]
    @ViewBuilder let card: (MetaPreview) -> Card

    var body: some View {
        ScrollView {
            if let title {
                ScreenTitle(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            PosterRows(titles: titles, card: card)
                .padding(.top, title == nil ? Metrics.screenPadding : Metrics.sectionSpacing)
                .padding(.bottom, Metrics.screenPadding)
        }
        .posterGridMargins()
    }
}

/// A `PosterGrid`'s rows without its scroll view, for a screen that scrolls them below its own
/// controls. Put them in a scroll view with `posterGridMargins()`.
struct PosterRows<Card: View>: View {
    @Environment(\.textLayout) private var textLayout
    let titles: [MetaPreview]
    @ViewBuilder let card: (MetaPreview) -> Card

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Metrics.shelfSpacing, alignment: .top),
                count: Lockup.poster.columns(textLayout)
            ),
            alignment: .leading, spacing: Metrics.sectionSpacing
        ) {
            ForEach(titles, content: card)
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }
}

extension ScrollView {
    /// Keeps a scroll view of `PosterRows` between the screen's margins, with lifted posters unclipped.
    func posterGridMargins() -> some View {
        // As safe area rather than padding, so each poster's `lockupFrame` divides only the width between the margins.
        safeAreaPadding(.horizontal, Metrics.screenPadding)
            .ignoresSafeArea(edges: .horizontal)
            .scrollClipDisabled()
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
                Artwork(url: item.background ?? item.poster, title: item.name.rawValue)
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
            .accessibilityLabel("\(item.name.rawValue), \(item.caption)")
            .accessibilityIdentifier("continueWatching.item")
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.rawValue).font(.caption).bold().labelLineLimit()
                Text(item.caption).font(.caption2).foregroundStyle(Palette.secondary)
            }
        }
        .lockupFrame(.wide)
    }
}

/// An episode's still, number, name and overview, ticked once watched. With spoilers hidden, an
/// unwatched episode blurs its still and leaves out its overview, unless it is the one playing.
/// `link` makes the still selectable, such as a link to the episode's streams.
struct EpisodeCard<Link: View>: View {
    @Environment(AppContext.self) private var app
    let video: Video
    /// The series' artwork, for an episode without a still.
    let fallbackArtwork: URL?
    var isPlaying = false
    @ViewBuilder let link: (EpisodeStill) -> Link

    var body: some View {
        let hidesSpoilers = !video.isWatched && !isPlaying && (app.preferences.state.preferences?.hidesSpoilers ?? false)
        VStack(alignment: .leading, spacing: Metrics.captionSpacing) {
            link(EpisodeStill(url: video.thumbnail ?? fallbackArtwork, title: video.name.rawValue, isBlurred: hidesSpoilers))
            HStack(spacing: 8) {
                if isPlaying {
                    Image(systemName: "play.fill").foregroundStyle(Palette.red).accessibilityLabel("Playing")
                } else if video.isWatched {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.secondary).accessibilityLabel("Watched")
                }
                Text("\(video.episode.map { "\($0). " } ?? "")\(video.name.rawValue)").bold().labelLineLimit()
            }
            .font(.caption)
            if let overview = video.overview, !hidesSpoilers {
                Text(overview.rawValue).font(.caption2).foregroundStyle(Palette.secondary).lineLimit(2)
            }
        }
        .lockupFrame(.wide)
    }
}

/// An episode's 16:9 still, blurred while it would spoil the episode.
struct EpisodeStill: View {
    let url: URL?
    let title: String
    let isBlurred: Bool

    var body: some View {
        Artwork(url: url, title: title)
            .aspectRatio(16 / 9, contentMode: .fit)
            .blur(radius: isBlurred ? Metrics.spoilerBlurRadius : 0, opaque: true)
            .clipShape(.rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
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
                .accessibilityAddTraits(.isHeader)
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
        modifier(LockupFrame(lockup: lockup))
    }
}

private struct LockupFrame: ViewModifier {
    @Environment(\.textLayout) private var textLayout
    let lockup: Lockup

    func body(content: Content) -> some View {
        content.containerRelativeFrame(
            .horizontal, count: lockup.columns(textLayout), spacing: Metrics.shelfSpacing, alignment: .leading
        )
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
