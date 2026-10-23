import SwiftUI

/// The titles the user added to their library, or the titles of one of their sources, as a grid of
/// posters of one type or all, in the order they pick. A picker chooses between the library and
/// each source. A long press on a library poster removes it.
struct LibraryScreen: View {
    /// The Library tab opens Your Library. A source's row on Home pushes the screen with the
    /// source picked, and then it draws its own title.
    enum Placement: Equatable {
        case tab
        case pushed(SourceID)
    }

    @Environment(AppContext.self) private var app
    var placement = Placement.tab
    @State private var store: FeatureStore<LibraryFeature>?

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            if let store {
                LibraryContent(store: store, drawsTitle: placement != .tab)
            }
        }
        .screenTitle("Library")
        .onAppear {
            guard store == nil else { return }
            let opening = LibraryFeature.opening(placement.collection)
            store = FeatureStore(
                opening.state, dependencies: LibraryFeature.Dependencies(library: app.services.library, sources: app.services.sources),
                start: opening.effects
            )
        }
    }
}

private extension LibraryScreen.Placement {
    var collection: LibraryFeature.Collection {
        switch self {
        case .tab: .yourLibrary
        case .pushed(let source): .source(source)
        }
    }
}

/// The filters and the grid scroll together in one scroll view at the screen's root. tvOS shows the
/// tab bar again from that scroll view's position; one only around the grid would leave the bar
/// hidden after a pushed screen, such as a long series' details, scrolled it away.
private struct LibraryContent: View {
    @Environment(AppContext.self) private var app
    let store: FeatureStore<LibraryFeature>
    let drawsTitle: Bool
    @State private var openFilter: LibraryFilters.Kind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if drawsTitle {
                    ScreenTitle("Library")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, Metrics.headerSpacing)
                }
                // In every state, so the screen always has something to focus.
                LibraryFilters(
                    listing: store.state.listing, types: types, sources: app.sources.state.sources, open: $openFilter,
                    pick: { store.send(.pick($0)) }, select: { store.send(.select($0)) }
                )
                Group {
                    switch store.state {
                    case .loading, .loadingSource:
                        ProgressView()
                            .containerRelativeFrame(.vertical)
                    case .loaded(let contents) where contents.titles.isEmpty:
                        LibraryEmpty(filter: contents.filter) { store.send(.select(.library($0))) }
                            .containerRelativeFrame(.vertical)
                    case .loaded(let contents):
                        PosterRows(titles: contents.titles) { preview in
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
                        .padding(.vertical, Metrics.screenPadding)
                    case .source(let titles) where titles.titles.isEmpty:
                        SourceEmpty(filter: titles.filter, name: sourceName(titles.filter.source)) { store.send(.select(.source($0))) }
                            .containerRelativeFrame(.vertical)
                    case .source(let titles):
                        VStack(spacing: Metrics.sectionSpacing) {
                            PosterRows(titles: titles.titles) { preview in
                                PosterCard(preview: preview)
                                    .onAppear {
                                        if preview == titles.titles.last { store.send(.loadMore) }
                                    }
                            }
                            if case .loadingMore = titles.paging {
                                ProgressView()
                            }
                        }
                        .padding(.vertical, Metrics.screenPadding)
                    case .sourceFailed(let filter, let error):
                        ContentUnavailableView {
                            Label("Couldn't Open \(sourceName(filter.source))", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error.message)
                        } actions: {
                            Button("Try Again") { store.send(.retry) }
                                .accessibilityIdentifier("library.retry")
                        }
                        .containerRelativeFrame(.vertical)
                    }
                }
                .frame(maxWidth: .infinity)
                // Keeps focus in an open filter's choices.
                .disabled(openFilter != nil)
            }
        }
        .posterGridMargins()
        .choiceMenus()
        // Without it the screen's identifier would replace its controls' own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.screen")
    }

    private var types: [ContentType] {
        if case .loaded(let contents) = store.state { contents.types } else { [] }
    }

    private func sourceName(_ id: SourceID) -> String {
        app.sources.state.sources.first { $0.id == id }?.name.text.rawValue ?? "This Source"
    }
}

private struct LibraryEmpty: View {
    let filter: LibraryFilter
    let select: (LibraryFilter) -> Void

    var body: some View {
        if let type = filter.type {
            ContentUnavailableView {
                Label("No \(type.pluralName) in Your Library", systemImage: "books.vertical")
            } actions: {
                Button("Show All") { select(LibraryFilter(type: nil, sort: filter.sort)) }
            }
        } else {
            ContentUnavailableView(
                "Your Library Is Empty", systemImage: "books.vertical",
                description: Text("Add movies and series from their page with Add to Library.")
            )
        }
    }
}

private struct SourceEmpty: View {
    let filter: SourceTitlesFilter
    let name: String
    let select: (SourceTitlesFilter) -> Void

    var body: some View {
        if let type = filter.type {
            ContentUnavailableView {
                Label("No \(type.pluralName) on \(name)", systemImage: "server.rack")
            } actions: {
                Button("Show All") { select(SourceTitlesFilter(source: filter.source, type: nil, sort: filter.sort)) }
            }
        } else {
            ContentUnavailableView(
                "Nothing to Play on \(name)", systemImage: "server.rack",
                description: Text("Its folders hold no videos Takane can play.")
            )
        }
    }
}

/// The library or source, the type and the sort above the grid, each a button that opens its
/// choices, and for a source, Browse Folders.
private struct LibraryFilters: View {
    enum Kind {
        case collection, type, sort
    }

    let listing: LibraryFeature.Listing
    /// The types the library holds.
    let types: [ContentType]
    let sources: [MediaSource]
    @Binding var open: Kind?
    let pick: (LibraryFeature.Collection) -> Void
    let select: (LibraryFeature.Listing) -> Void

    var body: some View {
        HStack(spacing: 24) {
            if !sources.isEmpty {
                ChoiceMenu(
                    title: "Library", label: collectionName, systemImage: collectionImage,
                    choices: [(name: "Your Library", value: .yourLibrary)] + sources.map { (name: $0.name.text.rawValue, value: .source($0.id)) },
                    selection: listing.collection, isPresented: presented(.collection), choose: pick
                )
                .disabled(isClosed(.collection))
                .accessibilityIdentifier("library.picker")
            }
            switch listing {
            case .library(let filter):
                typeMenu(filter.type, choices: libraryTypes(filter.type)) { select(.library(LibraryFilter(type: $0, sort: filter.sort))) }
                sortMenu(filter.sort, choices: LibrarySort.allCases.map { (name: $0.name, value: $0) }) {
                    select(.library(LibraryFilter(type: filter.type, sort: $0)))
                }
            case .source(let filter):
                typeMenu(filter.type, choices: [.movie, .series]) {
                    select(.source(SourceTitlesFilter(source: filter.source, type: $0, sort: filter.sort)))
                }
                sortMenu(filter.sort, choices: SourceSort.allCases.map { (name: $0.name, value: $0) }) {
                    select(.source(SourceTitlesFilter(source: filter.source, type: filter.type, sort: $0)))
                }
                if let source = sources.first(where: { $0.id == filter.source }) {
                    NavigationLink(value: Route.browsing(source)) {
                        Label("Browse Folders", systemImage: "folder")
                    }
                    .disabled(open != nil)
                    .accessibilityIdentifier("library.browse")
                }
            }
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func typeMenu(_ type: ContentType?, choices: [ContentType], choose: @escaping (ContentType?) -> Void) -> some View {
        ChoiceMenu(
            title: "Show", label: type?.pluralName ?? "All Types", systemImage: "line.3.horizontal.decrease",
            choices: [(name: "All Types", value: nil)] + choices.map { (name: $0.pluralName, value: Optional($0)) },
            selection: type, isPresented: presented(.type), choose: choose
        )
        .disabled(isClosed(.type))
        .accessibilityIdentifier("library.type")
    }

    private func sortMenu<Sort: Hashable>(_ sort: Sort, choices: [(name: String, value: Sort)], choose: @escaping (Sort) -> Void) -> some View {
        ChoiceMenu(
            title: "Sort By", label: "Sort: \(choices.first { $0.value == sort }?.name ?? "")", systemImage: "arrow.up.arrow.down",
            choices: choices, selection: sort, isPresented: presented(.sort), choose: choose
        )
        .disabled(isClosed(.sort))
        .accessibilityIdentifier("library.sort")
    }

    /// Another menu is open, which keeps focus in its choices.
    private func isClosed(_ kind: Kind) -> Bool {
        open != nil && open != kind
    }

    private func presented(_ kind: Kind) -> Binding<Bool> {
        Binding { open == kind } set: { open = $0 ? kind : nil }
    }

    private var collectionName: String {
        switch listing.collection {
        case .yourLibrary: "Your Library"
        case .source(let id): sources.first { $0.id == id }?.name.text.rawValue ?? "This Source"
        }
    }

    private var collectionImage: String {
        switch listing.collection {
        case .yourLibrary: "books.vertical"
        case .source: "server.rack"
        }
    }

    /// The library's types, and the chosen one after its last title went.
    private func libraryTypes(_ type: ContentType?) -> [ContentType] {
        guard let type, !types.contains(type) else { return types }
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

extension SourceSort {
    var name: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .name: "Name"
        case .year: "Year"
        }
    }
}
