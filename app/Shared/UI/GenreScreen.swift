import SwiftUI

/// One catalog's titles in one genre, as a grid of posters.
struct GenreScreen: View {
    @Environment(AppContext.self) private var app
    let filter: GenreFilter
    @State private var store: FeatureStore<GenreFeature>?

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            if let store {
                GenreContent(store: store)
            }
        }
        .navigationTitle(filter.title)
        .onAppear {
            guard store == nil else { return }
            store = FeatureStore(
                .loading(filter), dependencies: GenreFeature.Dependencies(catalog: app.services.catalog),
                start: [.load(filter)]
            )
        }
    }
}

private struct GenreContent: View {
    @Environment(\.textLayout) private var textLayout
    let store: FeatureStore<GenreFeature>
    /// Titles arrive after the screen opens; focus then moves to the first one.
    @FocusState private var focused: MediaID?

    var body: some View {
        Group {
            switch store.state {
            case .loading:
                CancellableProgress("Loading…")
            case .loaded(let filter, let titles) where titles.isEmpty:
                ContentUnavailableView {
                    Label("Nothing in \(filter.genre.rawValue)", systemImage: "film.stack")
                } description: {
                    Text("This catalog has no titles in this genre.")
                } actions: {
                    Button("Try Again") { store.send(.retry) }
                }
            case .loaded(_, let titles):
                ScrollView {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: Metrics.shelfSpacing, alignment: .top),
                            count: Lockup.poster.columns(textLayout)
                        ),
                        alignment: .leading, spacing: Metrics.sectionSpacing
                    ) {
                        ForEach(titles) { preview in
                            PosterCard(preview: preview).focused($focused, equals: preview.media)
                        }
                    }
                    .padding(.vertical, Metrics.screenPadding)
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }
                // As safe area rather than padding, so each poster's `lockupFrame` divides only the width between the margins.
                .safeAreaPadding(.horizontal, Metrics.screenPadding)
                .ignoresSafeArea(edges: .horizontal)
                .scrollClipDisabled()
            case .failed(let filter, let error):
                ContentUnavailableView {
                    Label("Couldn't Load \(filter.title)", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.message)
                } actions: {
                    Button("Try Again") { store.send(.retry) }
                }
            }
        }
        .accessibilityIdentifier("genre.screen")
        .onChange(of: firstTitle, initial: true) { _, first in
            if focused == nil { focused = first }
        }
    }

    private var firstTitle: MediaID? {
        if case .loaded(_, let titles) = store.state { titles.first?.media } else { nil }
    }
}

extension GenreFilter {
    /// "Action Movies".
    var title: String { "\(genre.rawValue) \(catalog.type.pluralName)" }
}

extension CatalogError {
    var message: String {
        switch self {
        case .addonFailed(let reason): "The add-on did not answer (\(reason))."
        }
    }
}
