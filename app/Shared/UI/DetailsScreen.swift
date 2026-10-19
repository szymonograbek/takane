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
                .loading(preview),
                dependencies: DetailsFeature.Dependencies(catalog: app.services.catalog, library: app.services.library),
                start: [.load(preview)]
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
                            let episodes = details.episodes(in: season)
                            let isSeasonWatched = episodes.allSatisfy(\.isWatched)
                            ForEach(episodes) { video in
                                EpisodeCard(video: video, show: details.preview, isSeasonWatched: isSeasonWatched) {
                                    store.send(.setWatched($0, $1))
                                }
                            }
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
                PlayButtons(preview: preview, details: details) { store.send(.setWatched(.title(preview.media), $0)) }
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
        if preview.type == .movie, details?.isWatched == true { parts.append("Watched") }
        return parts.joined(separator: " · ")
    }
}

/// Resume where the viewer stopped, or Play from the start. For a movie, a long press on either
/// marks it watched or unwatched.
private struct PlayButtons: View {
    @Environment(AppContext.self) private var app
    let preview: MetaPreview
    let details: TitleDetails?
    let setWatched: (Bool) -> Void

    var body: some View {
        HStack(spacing: 24) {
            let progress = app.home.state.progress(of: preview.media)
            if let progress {
                NavigationLink(value: Route.streams(StreamsRequest(preview: preview, video: progress.video))) {
                    Label("Resume · \(progress.caption)", systemImage: "play.fill")
                }
                .primaryActionStyle()
                .contextMenu { movieMenu }
                .accessibilityIdentifier("details.resume")
            }
            if let first = details?.firstPlayable {
                let play = NavigationLink(value: Route.streams(StreamsRequest(preview: preview, video: first))) {
                    Label(preview.type == .movie ? "Play" : "Play First Episode", systemImage: "play.fill")
                }
                .contextMenu { movieMenu }
                .accessibilityIdentifier("details.play")
                // With Resume on screen, starting over is the secondary action.
                if progress == nil { play.primaryActionStyle() } else { play }
            }
        }
    }

    /// A series is marked by season and episode instead, since marking it whole leaves its episodes as they were.
    @ViewBuilder private var movieMenu: some View {
        if let details, preview.type == .movie {
            WatchedButton(isWatched: details.isWatched, action: setWatched)
        }
    }
}

/// An episode's still, number, name and overview, ticked once watched. With spoilers hidden, an
/// unwatched episode blurs its still and leaves out its overview. A long press marks the episode
/// or its season.
private struct EpisodeCard: View {
    @Environment(AppContext.self) private var app
    let video: Video
    let show: MetaPreview
    let isSeasonWatched: Bool
    let setWatched: (WatchedTarget, Bool) -> Void

    var body: some View {
        let hidesSpoilers = !video.isWatched && (app.preferences.state.preferences?.hidesSpoilers ?? false)
        VStack(alignment: .leading, spacing: Metrics.captionSpacing) {
            NavigationLink(value: Route.streams(StreamsRequest(preview: show, video: video.playable))) {
                Artwork(url: video.thumbnail ?? show.background, title: video.name)
                    .frame(width: Metrics.wideCardWidth, height: Metrics.wideCardWidth * 9 / 16)
                    .blur(radius: hidesSpoilers ? Metrics.spoilerBlurRadius : 0, opaque: true)
                    .clipShape(.rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
            }
            .cardButtonStyle()
            .contextMenu {
                WatchedButton(isWatched: video.isWatched) { setWatched(.video(video.playable), $0) }
                if let season = video.season {
                    WatchedButton(isWatched: isSeasonWatched, of: "Season") { setWatched(.season(show.media, season), $0) }
                }
            }
            .accessibilityIdentifier("episode.\(video.playable.rawValue)")
            HStack(spacing: 8) {
                if video.isWatched {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.secondary).accessibilityLabel("Watched")
                }
                Text("\(video.episode.map { "\($0). " } ?? "")\(video.name)").bold().lineLimit(1)
            }
            .font(.caption)
            if let overview = video.overview, !hidesSpoilers {
                Text(overview).font(.caption2).foregroundStyle(Palette.secondary).lineLimit(2)
            }
        }
        .frame(width: Metrics.wideCardWidth, alignment: .leading)
    }
}

/// "Mark as Watched" or, for something already watched, "Mark as Unwatched". `of` names what a
/// broader mark covers, as in "Mark Season as Watched". The action gets the mark to set.
private struct WatchedButton: View {
    let isWatched: Bool
    var of: String?
    let action: (Bool) -> Void

    var body: some View {
        let subject = of.map { " \($0)" } ?? ""
        Button(
            isWatched ? "Mark\(subject) as Unwatched" : "Mark\(subject) as Watched",
            systemImage: isWatched ? "circle" : "checkmark.circle"
        ) { action(!isWatched) }
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
