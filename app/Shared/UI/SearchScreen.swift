import SwiftUI

/// Searches every add-on that can, showing each catalog's answers as a row.
struct SearchScreen: View {
    @Environment(AppContext.self) private var app
    @State private var store: FeatureStore<SearchFeature>?
    @State private var query = ""

    var body: some View {
        ScrollView {
            if let store {
                SearchResultsView(state: store.state)
            }
        }
        .scrollClipDisabled()
        .background(Palette.canvas.ignoresSafeArea())
        .searchable(text: $query, prompt: "Movies and series")
        .onChange(of: query) { _, text in store?.send(.queryChanged(SearchText(text))) }
        .onAppear {
            guard store == nil else { return }
            store = FeatureStore(.empty, dependencies: SearchFeature.Dependencies(catalog: app.services.catalog))
        }
    }
}

private struct SearchResultsView: View {
    let state: SearchFeature.State

    var body: some View {
        switch state {
        case .empty:
            ContentUnavailableView(
                "Search Your Add-ons", systemImage: "magnifyingglass",
                description: Text("Find movies and series across every add-on that can search.")
            )
        case .searching(_, results: nil), .searching(_, results: .searching?):
            ProgressView().padding(80)
        case .searching(_, results: .noSearchAddons?):
            ContentUnavailableView(
                "No Add-on Can Search", systemImage: "puzzlepiece.extension",
                description: Text("Install a catalog add-on such as Cinemeta in Settings › Add-ons.")
            )
        case .searching(let text, results: .rows(_, let rows)?):
            let found = rows.filter { !($0.items.value ?? []).isEmpty }
            if found.isEmpty && rows.allSatisfy(\.items.isSettled) {
                ContentUnavailableView.search(text: text.rawValue)
            } else {
                LazyVStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    ForEach(found) { row in
                        Shelf(title: row.id.type.pluralName) {
                            ForEach(row.items.value ?? []) { PosterCard(preview: $0) }
                        }
                    }
                }
                .padding(.vertical, Metrics.sectionSpacing)
            }
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
