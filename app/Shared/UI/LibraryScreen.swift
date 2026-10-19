import SwiftUI

/// The titles the user added to their library, as a grid of posters of one type or all, in the
/// order they pick. A long press on a poster removes it.
struct LibraryScreen: View {
    @Environment(AppContext.self) private var app
    @State private var store: FeatureStore<LibraryFeature>?

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            if let store {
                LibraryContent(store: store)
            }
        }
        .screenTitle("Library")
        .onAppear {
            guard store == nil else { return }
            let filter = LibraryFeature.defaultFilter
            store = FeatureStore(
                .loading(filter), dependencies: LibraryFeature.Dependencies(library: app.services.library),
                start: [.observe(filter)]
            )
        }
    }
}

private struct LibraryContent: View {
    let store: FeatureStore<LibraryFeature>
    @State private var openFilter: LibraryFilters.Kind?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // In every state, so the screen always has something to focus.
            LibraryFilters(filter: store.state.filter, types: types, open: $openFilter) { store.send(.select($0)) }
            Group {
                switch store.state {
                case .loading:
                    ProgressView()
                case .loaded(let contents) where contents.titles.isEmpty:
                    if let type = contents.filter.type {
                        ContentUnavailableView {
                            Label("No \(type.pluralName) in Your Library", systemImage: "books.vertical")
                        } actions: {
                            Button("Show All") { store.send(.select(LibraryFilter(type: nil, sort: contents.filter.sort))) }
                        }
                    } else {
                        ContentUnavailableView(
                            "Your Library Is Empty", systemImage: "books.vertical",
                            description: Text("Add movies and series from their page with Add to Library.")
                        )
                    }
                case .loaded(let contents):
                    PosterGrid(titles: contents.titles) { preview in
                        PosterCard(preview: preview)
                            .contextMenu {
                                Button("Remove from Library", systemImage: "minus.circle", role: .destructive) {
                                    store.send(.remove(preview.media))
                                }
                            }
                            .onAppear {
                                if preview == contents.titles.last { store.send(.loadMore) }
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Keeps focus in an open filter's choices.
            .disabled(openFilter != nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .choiceMenus()
        // The grid and the filters draw their own margins.
        .ignoresSafeArea(edges: .horizontal)
        // Without it the screen's identifier would replace its controls' own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.screen")
    }

    private var types: [ContentType] {
        if case .loaded(let contents) = store.state { contents.types } else { [] }
    }
}

/// The type and sort above the grid, each a button that opens its choices.
private struct LibraryFilters: View {
    enum Kind {
        case type, sort
    }

    let filter: LibraryFilter
    /// The types the library holds.
    let types: [ContentType]
    @Binding var open: Kind?
    let select: (LibraryFilter) -> Void

    var body: some View {
        HStack(spacing: 24) {
            ChoiceMenu(
                title: "Show", label: filter.type?.pluralName ?? "All Types", systemImage: "line.3.horizontal.decrease",
                choices: [(name: "All Types", value: nil)] + choices.map { (name: $0.pluralName, value: Optional($0)) },
                selection: filter.type, isPresented: presented(.type)
            ) { select(LibraryFilter(type: $0, sort: filter.sort)) }
            .disabled(open == .sort)
            .accessibilityIdentifier("library.type")
            ChoiceMenu(
                title: "Sort By", label: "Sort: \(filter.sort.name)", systemImage: "arrow.up.arrow.down",
                choices: LibrarySort.allCases.map { (name: $0.name, value: $0) },
                selection: filter.sort, isPresented: presented(.sort)
            ) { select(LibraryFilter(type: filter.type, sort: $0)) }
            .disabled(open == .type)
            .accessibilityIdentifier("library.sort")
        }
        .padding(.horizontal, Metrics.screenPadding)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func presented(_ kind: Kind) -> Binding<Bool> {
        Binding { open == kind } set: { open = $0 ? kind : nil }
    }

    /// The library's types, and the chosen one after its last title went.
    private var choices: [ContentType] {
        guard let type = filter.type, !types.contains(type) else { return types }
        return types + [type]
    }
}

extension LibrarySort {
    var name: String {
        switch self {
        case .recentlyWatched: "Recently Watched"
        case .name: "Name"
        case .unwatchedFirst: "Unwatched First"
        }
    }
}
