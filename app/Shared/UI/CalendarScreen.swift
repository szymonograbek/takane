import SwiftUI

/// The episodes of the library's shows that come out from today on, one row per day.
struct CalendarScreen: View {
    @Environment(AppContext.self) private var app
    @State private var store: FeatureStore<CalendarFeature>?

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            if let store {
                CalendarContent(store: store)
            }
        }
        .navigationTitle("Calendar")
        #if os(tvOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .onAppear {
            if store == nil {
                store = FeatureStore(.loading, dependencies: CalendarFeature.Dependencies(library: app.services.library))
            }
            // Shows added since the last visit join in.
            store?.send(.appeared)
        }
    }
}

private struct CalendarContent: View {
    let store: FeatureStore<CalendarFeature>

    var body: some View {
        Group {
            switch store.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let episodes):
                let days = ReleaseSchedule.days(episodes, today: .now, calendar: .current)
                if days.isEmpty {
                    ContentUnavailableView(
                        "Nothing Coming Up", systemImage: "calendar",
                        description: Text("New episodes of the series in your library show here once their release dates are known.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                            ForEach(days) { day in
                                Shelf(title: day.label) {
                                    ForEach(day.episodes) { episode in
                                        UpcomingCard(episode: episode)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, Metrics.screenPadding)
                    }
                    .scrollClipDisabled()
                    // Shelves draw their own margins.
                    .ignoresSafeArea(edges: .horizontal)
                }
            case .failed(let error):
                ContentUnavailableView {
                    Label("Couldn't Load the Calendar", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.message)
                } actions: {
                    Button("Try Again") { store.send(.retry) }
                }
            }
        }
        // Without it the screen's identifier would replace its controls' own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.screen")
    }
}

/// An upcoming episode: its show's wide artwork, the show's name, and the episode's number and
/// name. Selecting it opens the show.
private struct UpcomingCard: View {
    let episode: UpcomingEpisode

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.captionSpacing) {
            NavigationLink(value: Route.details(episode.show)) {
                Artwork(url: episode.show.background ?? episode.show.poster, title: episode.show.name)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
            }
            .cardButtonStyle()
            .accessibilityLabel("\(episode.show.name), \(caption)")
            .accessibilityIdentifier("upcoming.\(episode.video.rawValue)")
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.show.name).font(.caption).bold().labelLineLimit()
                Text(caption).font(.caption2).foregroundStyle(Palette.secondary).labelLineLimit()
            }
        }
        .lockupFrame(.wide)
    }

    /// "S2 · E5 · The Rains of Castamere".
    private var caption: String {
        guard case .episode(_, let season, let number) = episode.video else { return episode.name }
        return "S\(season) · E\(number) · \(episode.name)"
    }
}
