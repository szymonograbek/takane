import SwiftUI

/// Searches every add-on that can, showing each catalog's answers as a row. Before anything is
/// typed, offers recent searches.
struct SearchScreen: View {
    @Environment(AppContext.self) private var app
    @State private var store: FeatureStore<SearchFeature>?
    @State private var query = ""

    var body: some View {
        ScrollView {
            if let store {
                SearchResultsView(store: store) { query = $0.rawValue }
            }
        }
        .scrollClipDisabled()
        // The search container proposes no width, so the scroll view would hug its content.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas.ignoresSafeArea())
        .searchable(text: $query, prompt: "Movies and series")
        .onChange(of: query) { _, text in store?.send(.queryChanged(SearchText(text))) }
        .onAppear {
            guard store == nil else { return }
            store = FeatureStore(
                SearchFeature.State(), dependencies: SearchFeature.Dependencies(catalog: app.services.catalog),
                start: [.observeRecentSearches]
            )
        }
    }
}

private struct SearchResultsView: View {
    let store: FeatureStore<SearchFeature>
    /// Puts a search in the search field, which runs it.
    let search: (SearchText) -> Void

    var body: some View {
        switch store.state.query {
        case .empty:
            switch store.state.recentSearches {
            case nil:
                EmptyView()
            case let searches? where searches.isEmpty:
                ContentUnavailableView(
                    "Search Your Add-ons", systemImage: "magnifyingglass",
                    description: Text("Find movies and series across every add-on that can search.")
                )
            case let searches?:
                RecentSearchesShelf(searches: searches, search: search) { store.send(.clearRecentSearches) }
                    .padding(.vertical, Metrics.sectionSpacing)
            }
        case .searching(_, results: nil), .searching(_, results: .searching?):
            ProgressView().padding(80)
        case .searching(_, results: .noSearchAddons?):
            ContentUnavailableView(
                "No Add-on Can Search", systemImage: "puzzlepiece.extension",
                description: Text("Install a catalog add-on such as Cinemeta in Settings › Add-ons.")
            )
        case .searching(let text, results: .rows(_, let rows)?):
            // Loading rows hold their place, so rows that answer late don't push the others around.
            let shown = rows.filter { !$0.items.isSettled || !($0.items.value ?? []).isEmpty }
            if shown.isEmpty {
                ContentUnavailableView.search(text: text.rawValue)
            } else {
                LazyVStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    ForEach(shown) { row in
                        Shelf(title: row.id.type.pluralName) {
                            if let items = row.items.value {
                                ForEach(items) { PosterCard(preview: $0) }
                            } else {
                                PosterPlaceholders()
                            }
                        }
                    }
                }
                .padding(.vertical, Metrics.sectionSpacing)
            }
        }
    }
}

/// The last few searches, each a button that runs it again, then one that forgets them all.
private struct RecentSearchesShelf: View {
    let searches: [SearchText]
    let search: (SearchText) -> Void
    let clear: () -> Void
    @State private var isConfirmingClear = false

    var body: some View {
        Shelf(title: "Recent Searches") {
            ForEach(searches.prefix(6), id: \.self) { text in
                Button(text.rawValue) { search(text) }
                    .accessibilityIdentifier("search.recent")
            }
            Button("Clear", systemImage: "xmark.circle") { isConfirmingClear = true }
                .accessibilityIdentifier("search.clearRecent")
        }
        .confirmationDialog("Clear recent searches?", isPresented: $isConfirmingClear) {
            Button("Clear Recent Searches", action: clear)
        }
    }
}

extension ContentType {
    /// "Movies", "Series", or the add-on's own type name.
    var pluralName: String {
        switch self {
        case .movie: "Movies"
        case .series: "Series"
        default: rawValue.capitalized
        }
    }
}
