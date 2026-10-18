import SwiftUI

/// A featured title, then continue watching, then every add-on catalog.
struct HomeScreen: View {
    @Environment(AppContext.self) private var app

    var body: some View {
        let home = app.home.state
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                if let featured = home.featured {
                    Hero(preview: featured)
                }
                if !home.continueWatching.isEmpty {
                    ContinueWatchingShelf(items: home.continueWatching)
                }
                Discover(board: home.board)
            }
            .padding(.bottom, Metrics.sectionSpacing)
        }
        .scrollClipDisabled()
        // Rows pad themselves, so artwork can run to the screen's edges.
        .ignoresSafeArea(edges: [.top, .horizontal])
        .accessibilityIdentifier("home.screen")
        .background(Palette.canvas.ignoresSafeArea())
        .navigationTitle("Home")
        #if os(tvOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

/// The first catalog title with wide artwork, large, with Play and Details.
private struct Hero: View {
    let preview: MetaPreview

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(url: preview.background, title: nil)
                .frame(height: Metrics.heroHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay {
                    LinearGradient(colors: [Palette.canvas.opacity(0.9), .clear], startPoint: .leading, endPoint: .center)
                    LinearGradient(colors: [.clear, Palette.canvas], startPoint: .center, endPoint: .bottom)
                }
            VStack(alignment: .leading, spacing: 16) {
                TitleMark(name: preview.name, logo: preview.logo)
                if let year = preview.releaseInfo {
                    Text(year).font(.caption).foregroundStyle(Palette.secondary)
                }
                if let description = preview.description {
                    Text(description).font(.callout).lineLimit(2).frame(maxWidth: 760, alignment: .leading)
                }
                HStack(spacing: 24) {
                    if preview.type == .movie {
                        NavigationLink(value: Route.streams(StreamsRequest(preview: preview, video: .movie(preview.media)))) {
                            Label("Play", systemImage: "play.fill")
                        }
                        .primaryActionStyle()
                        .accessibilityIdentifier("hero.play")
                    }
                    NavigationLink(value: Route.details(preview)) {
                        Label("Details", systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("hero.details")
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 40)
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }
}

/// A title's logo when the add-on has one, its name otherwise.
struct TitleMark: View {
    let name: String
    let logo: URL?

    var body: some View {
        AsyncImage(url: logo) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFit().frame(maxWidth: 560, maxHeight: 160, alignment: .leading)
            } else {
                Text(name).font(.largeTitle).bold().lineLimit(2)
            }
        }
        .accessibilityLabel(name)
    }
}

private struct ContinueWatchingShelf: View {
    @Environment(AppContext.self) private var app
    let items: [ContinueWatchingItem]

    var body: some View {
        Shelf(title: "Continue Watching") {
            ForEach(items) { item in
                ContinueCard(item: item) { app.home.send(.removeFromContinueWatching(item.media)) }
            }
        }
    }
}

/// Every catalog row, or what to do when there are none.
private struct Discover: View {
    @Environment(AppContext.self) private var app
    let board: Board

    var body: some View {
        switch board {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(60)
        case .noCatalogAddons:
            ContentUnavailableView {
                Label("Nothing to Discover Yet", systemImage: "puzzlepiece.extension")
            } description: {
                Text("Install a catalog add-on such as Cinemeta in Settings › Add-ons.")
            }
        case .rows(let rows):
            ForEach(rows) { row in
                CatalogShelf(row: row) { app.home.send(.loadMore(row.id)) }
            }
        }
    }
}

private struct CatalogShelf: View {
    let row: CatalogRow
    let loadMore: () -> Void

    var body: some View {
        switch row.items {
        case .loading:
            Shelf(title: row.title) {
                ForEach(0..<6, id: \.self) { _ in
                    Palette.surface
                        .frame(width: Metrics.posterWidth, height: Metrics.posterWidth * 1.5)
                        .clipShape(.rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
                }
            }
        case .failed:
            // A failing add-on hides its own row rather than breaking the screen.
            EmptyView()
        case .loaded(let items) where items.isEmpty:
            EmptyView()
        case .loaded(let items):
            Shelf(title: row.title) {
                ForEach(items) { preview in
                    PosterCard(preview: preview)
                        .onAppear { if preview == items.last { loadMore() } }
                }
            }
        }
    }
}

extension ContinueWatchingItem {
    var streamsRequest: StreamsRequest {
        StreamsRequest(video: video, title: name, backdrop: background ?? poster)
    }
}

extension StreamsRequest {
    init(preview: MetaPreview, video: PlayableID) {
        self.init(video: video, title: preview.name, backdrop: preview.background ?? preview.poster)
    }
}

extension CatalogRow {
    /// "Popular Movies": the catalog's name with its type, since add-ons reuse names across types.
    var title: String {
        let type = id.type.pluralName
        return name.localizedCaseInsensitiveContains(type) ? name : "\(name) \(type)"
    }
}
