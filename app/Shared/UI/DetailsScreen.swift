import SwiftUI

/// One title: backdrop, what it is, Play or Resume, and for a series its episodes by season.
struct DetailsScreen: View {
    @Environment(AppContext.self) private var app
    let preview: MetaPreview
    @State private var store: FeatureStore<DetailsFeature>?

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            if let store {
                DetailsContent(store: store)
            }
        }
        .onAppear {
            guard store == nil else { return }
            store = FeatureStore(
                .loading(preview), dependencies: DetailsFeature.Dependencies(catalog: app.services.catalog), start: [.load(preview)]
            )
        }
    }
}

private struct DetailsContent: View {
    @Environment(AppContext.self) private var app
    let store: FeatureStore<DetailsFeature>

    var body: some View {
        let state = store.state
        let preview = state.preview
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                header(preview, details: state.details)
                switch state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .failed(_, let error):
                    ContentUnavailableView {
                        Label("Couldn't Load This Title", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error.message)
                    } actions: {
                        Button("Try Again") { store.send(.retry) }
                    }
                case .loaded(let details) where !details.seasons.isEmpty:
                    ForEach(details.seasons, id: \.self) { season in
                        Shelf(title: season == 0 ? "Specials" : "Season \(season)") {
                            ForEach(details.episodes(in: season)) { EpisodeCard(video: $0, show: details.preview) }
                        }
                    }
                case .loaded:
                    EmptyView()
                }
            }
            .padding(.bottom, Metrics.sectionSpacing)
        }
        .scrollClipDisabled()
        .ignoresSafeArea(edges: [.top, .horizontal])
    }

    private func header(_ preview: MetaPreview, details: TitleDetails?) -> some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(url: preview.background ?? preview.poster, title: nil)
                .frame(height: Metrics.heroHeight * 1.2)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay {
                    LinearGradient(colors: [Palette.canvas.opacity(0.95), .clear], startPoint: .leading, endPoint: .center)
                    LinearGradient(colors: [.clear, Palette.canvas], startPoint: .center, endPoint: .bottom)
                }
            VStack(alignment: .leading, spacing: 16) {
                TitleMark(name: preview.name, logo: preview.logo)
                Text(metadata(preview, details: details)).font(.caption).foregroundStyle(Palette.secondary)
                if let description = preview.description {
                    Text(description).font(.callout).lineLimit(4).frame(maxWidth: 900, alignment: .leading)
                }
                PlayButtons(preview: preview, details: details)
                    .padding(.top, 8)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 30)
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func metadata(_ preview: MetaPreview, details: TitleDetails?) -> String {
        var parts = [preview.releaseInfo, details?.runtime].compactMap(\.self)
        if let genres = details?.genres, !genres.isEmpty { parts.append(genres.prefix(3).joined(separator: ", ")) }
        if let rating = details?.imdbRating { parts.append("★ \(rating)") }
        return parts.joined(separator: " · ")
    }
}

/// Resume where the viewer stopped, or Play from the start.
private struct PlayButtons: View {
    @Environment(AppContext.self) private var app
    let preview: MetaPreview
    let details: TitleDetails?

    var body: some View {
        HStack(spacing: 24) {
            let progress = app.home.state.progress(of: preview.media)
            if let progress {
                NavigationLink(value: Route.streams(StreamsRequest(preview: preview, video: progress.video))) {
                    Label("Resume · \(progress.remainingLabel)", systemImage: "play.fill")
                }
                .primaryActionStyle()
                .accessibilityIdentifier("details.resume")
            }
            if let first = details?.firstPlayable {
                let play = NavigationLink(value: Route.streams(StreamsRequest(preview: preview, video: first))) {
                    Label(preview.type == .movie ? "Play" : "Play First Episode", systemImage: "play.fill")
                }
                .accessibilityIdentifier("details.play")
                // With Resume on screen, starting over is the secondary action.
                if progress == nil { play.primaryActionStyle() } else { play }
            }
        }
    }
}

private struct EpisodeCard: View {
    let video: Video
    let show: MetaPreview

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.captionSpacing) {
            NavigationLink(value: Route.streams(StreamsRequest(preview: show, video: video.playable))) {
                Artwork(url: video.thumbnail ?? show.background, title: video.name)
                    .frame(width: Metrics.wideCardWidth, height: Metrics.wideCardWidth * 9 / 16)
                    .clipShape(.rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
            }
            .cardButtonStyle()
            .accessibilityIdentifier("episode.\(video.playable.rawValue)")
            Text("\(video.episode.map { "\($0). " } ?? "")\(video.name)").font(.caption).bold().lineLimit(1)
            if let overview = video.overview {
                Text(overview).font(.caption2).foregroundStyle(Palette.secondary).lineLimit(2)
            }
        }
        .frame(width: Metrics.wideCardWidth, alignment: .leading)
    }
}

extension DetailsError {
    var message: String {
        switch self {
        case .noMetaAddons: "No installed add-on describes this kind of title."
        case .notFound: "None of your add-ons know this title."
        case .unavailable(let reason): "The add-ons did not answer (\(reason))."
        }
    }
}
