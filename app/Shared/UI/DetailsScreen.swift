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

private enum DetailsFocus: Hashable {
    case resume, play
}

private struct DetailsContent: View {
    @Environment(AppContext.self) private var app
    @Environment(\.dismiss) private var dismiss
    let store: FeatureStore<DetailsFeature>
    @FocusState private var focus: DetailsFocus?

    var body: some View {
        let state = store.state
        let preview = state.preview
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                header(preview, details: state.details)
                switch state {
                case .loading:
                    CancellableProgress("Loading…")
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
                case .loaded(let details) where details.firstPlayable == nil:
                    ContentUnavailableView {
                        Label("No Episodes Yet", systemImage: "tv")
                    } description: {
                        Text("Your add-ons list no episodes for this series.")
                    } actions: {
                        // Also gives the screen something to focus, so Menu goes back from it.
                        Button("Go Back") { dismiss() }
                            .accessibilityIdentifier("details.back")
                    }
                case .loaded:
                    EmptyView()
                }
            }
            .padding(.bottom, Metrics.sectionSpacing)
        }
        .scrollClipDisabled()
        .ignoresSafeArea(edges: [.top, .horizontal])
        .defaultFocus($focus, playFocus)
        .onChange(of: state.details == nil) { _, isLoading in
            if !isLoading, focus == nil { focus = playFocus }
        }
    }

    /// Resume, else Play: where focus lands when the page opens and again when its details arrive.
    private var playFocus: DetailsFocus? {
        if app.home.state.progress(of: store.state.preview.media) != nil { return .resume }
        return store.state.details?.firstPlayable == nil ? nil : .play
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
                TitleMark(name: preview.name.rawValue, logo: preview.logo)
                Text(metadata(preview, details: details)).font(.caption).foregroundStyle(Palette.secondary)
                if let description = preview.description {
                    DescriptionButton(title: preview.name.rawValue, text: description.rawValue)
                        .accessibilityIdentifier("details.description")
                }
                PlayButtons(
                    preview: preview, details: details, focus: $focus,
                    setWatched: { store.send(.setWatched(.title(preview.media), $0)) },
                    setInLibrary: { store.send(.setInLibrary($0)) },
                    rate: { store.send(.rate($0)) }
                )
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
        var parts = [preview.releaseInfo?.rawValue, details?.runtime].compactMap(\.self)
        if let genres = details?.genres, !genres.isEmpty { parts.append(genres.prefix(3).joined(separator: ", ")) }
        if let rating = details?.imdbRating { parts.append("★ \(rating)") }
        if preview.type == .movie, details?.isWatched == true { parts.append("Watched") }
        return parts.joined(separator: " · ")
    }
}

/// Resume where the viewer stopped, or Play from the start, then adding the title to the library or
/// taking it out, and liking or loving it. For a movie, a long press on Resume or Play marks it
/// watched or unwatched.
private struct PlayButtons: View {
    @Environment(AppContext.self) private var app
    let preview: MetaPreview
    let details: TitleDetails?
    let focus: FocusState<DetailsFocus?>.Binding
    let setWatched: (Bool) -> Void
    let setInLibrary: (Bool) -> Void
    let rate: (TitleRating?) -> Void

    var body: some View {
        HStack(spacing: 24) {
            let progress = app.home.state.progress(of: preview.media)
            if let progress {
                NavigationLink(value: Route.streams(StreamsRequest(preview: preview, video: progress.video))) {
                    Label("Resume · \(progress.caption)", systemImage: "play.fill")
                }
                .primaryActionStyle()
                .contextMenu { movieMenu }
                .focused(focus, equals: .resume)
                .accessibilityIdentifier("details.resume")
            }
            if let first = details?.firstPlayable {
                let play = NavigationLink(value: Route.streams(StreamsRequest(preview: preview, video: first))) {
                    Label(preview.playable == nil ? "Play First Episode" : "Play", systemImage: "play.fill")
                }
                .contextMenu { movieMenu }
                .focused(focus, equals: .play)
                .accessibilityIdentifier("details.play")
                // With Resume on screen, starting over is the secondary action.
                if progress == nil { play.primaryActionStyle() } else { play }
            }
            if let details {
                Button { setInLibrary(!details.isInLibrary) } label: {
                    Label(details.isInLibrary ? "In Library" : "Add to Library", systemImage: details.isInLibrary ? "checkmark" : "plus")
                }
                .accessibilityIdentifier("details.library")
                if details.rating != .unavailable {
                    let current: TitleRating? = if case .rated(let rating) = details.rating { rating } else { nil }
                    SegmentedButtons {
                        rateButton(.liked, current: current)
                        rateButton(.loved, current: current)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Selecting the current rating clears it. Never disabled, since disabling a focused button on
    /// tvOS moves focus away.
    private func rateButton(_ rating: TitleRating, current: TitleRating?) -> some View {
        let isSelected = rating == current
        let (title, symbol, id) = switch rating {
        case .liked: ("Like", "hand.thumbsup", "details.like")
        case .loved: ("Love", "heart", "details.love")
        }
        return Button { rate(isSelected ? nil : rating) } label: {
            Label(title, systemImage: isSelected ? "\(symbol).fill" : symbol)
                .labelStyle(.iconOnly)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    /// A series is marked by season and episode instead, since marking it whole leaves its episodes as they were.
    @ViewBuilder private var movieMenu: some View {
        if let details, preview.type == .movie {
            WatchedButton(isWatched: details.isWatched, action: setWatched)
        }
    }
}

/// The description cut to four lines. Selecting it opens the whole text, which Back closes.
private struct DescriptionButton: View {
    let title: String
    let text: String
    @State private var isExpanded = false

    var body: some View {
        Button { isExpanded = true } label: {
            Text(text)
                .font(.callout)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 900, alignment: .leading)
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .fullScreenCover(isPresented: $isExpanded) { FullDescription(title: title, text: text) }
        #else
        .sheet(isPresented: $isExpanded) { FullDescription(title: title, text: text) }
        #endif
    }
}

private struct FullDescription: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            Text(title).font(.title2).bold()
            ScrollView {
                Text(text).frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Done") { dismiss() }
                .accessibilityIdentifier("details.descriptionDone")
        }
        .frame(maxWidth: Metrics.readingWidth)
        .padding(Metrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas.ignoresSafeArea())
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
                Artwork(url: video.thumbnail ?? show.background, title: video.name.rawValue)
                    .aspectRatio(16 / 9, contentMode: .fit)
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
