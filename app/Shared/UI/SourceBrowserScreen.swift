import SwiftUI

/// One folder of a source: its folders and episode files as a list, then its titles as posters.
/// A folder pushes another of these; a title or an episode opens the title's details.
struct SourceBrowserScreen: View {
    @Environment(AppContext.self) private var app
    let folder: SourceBrowserFeature.Folder
    let name: Redacted<String>
    @State private var store: FeatureStore<SourceBrowserFeature>?

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            if let store {
                SourceBrowserContent(store: store, title: name.rawValue)
            }
        }
        .screenTitle(name.rawValue)
        .onAppear {
            guard store == nil else { return }
            store = FeatureStore(
                .loading(folder), dependencies: SourceBrowserFeature.Dependencies(sources: app.services.sources),
                start: [.list(folder)]
            )
        }
    }
}

private struct SourceBrowserContent: View {
    let store: FeatureStore<SourceBrowserFeature>
    let title: String
    /// Entries arrive after the screen opens; focus then moves to the first one.
    @FocusState private var focused: SourceEntry?

    var body: some View {
        Group {
            switch store.state {
            case .loading:
                CancellableProgress("Loading…").titled(title)
            case .loaded(_, let entries) where entries.isEmpty:
                ContentUnavailableView {
                    Label("Nothing to Play", systemImage: "folder")
                } description: {
                    Text("This folder holds no videos Takane can play.")
                } actions: {
                    Button("Try Again") { store.send(.retry) }
                        .accessibilityIdentifier("browser.retry")
                }
                .titled(title)
            case .loaded(let folder, let entries):
                FolderContents(folder: folder, title: title, entries: entries, focused: $focused)
            case .failed(_, let error):
                ContentUnavailableView {
                    Label("Couldn't Open \(title)", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.message)
                } actions: {
                    Button("Try Again") { store.send(.retry) }
                        .accessibilityIdentifier("browser.retry")
                }
                .titled(title)
            }
        }
        .accessibilityIdentifier("browser.screen")
        .onChange(of: first, initial: true) { _, first in
            if focused == nil { focused = first }
        }
    }

    /// The entry drawn first: the list's first row, else the first poster.
    private var first: SourceEntry? {
        guard case .loaded(_, let entries) = store.state else { return nil }
        return entries.first { !$0.isPoster } ?? entries.first
    }
}

/// The folder's rows above its posters, in one scroll view with the title, so the title scrolls away.
private struct FolderContents: View {
    let folder: SourceBrowserFeature.Folder
    let title: String
    let entries: [SourceEntry]
    let focused: FocusState<SourceEntry?>.Binding

    var body: some View {
        let rows = entries.filter { !$0.isPoster }
        let titles = entries.compactMap(\.poster)
        ScrollView {
            ScreenTitle(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                        ForEach(rows, id: \.self, content: row)
                    }
                    .frame(maxWidth: Metrics.formWidth, alignment: .leading)
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }
                if !titles.isEmpty {
                    PosterRows(titles: titles) { preview in
                        PosterCard(preview: preview).focused(focused, equals: .title(preview))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Metrics.sectionSpacing)
        }
        .posterGridMargins()
    }

    @ViewBuilder
    private func row(_ entry: SourceEntry) -> some View {
        switch entry {
        case .folder(let id, let name):
            NavigationLink(value: Route.sourceFolder(SourceBrowserFeature.Folder(source: folder.source, id: id), name: name)) {
                Label(name.rawValue, systemImage: "folder").frame(maxWidth: .infinity, alignment: .leading)
            }
            .focused(focused, equals: entry)
            .accessibilityIdentifier("browser.folder")
        case .episode(let show, let season, let episode, let name):
            NavigationLink(value: Route.details(show)) {
                Label("S\(season) E\(episode) · \(name.rawValue)", systemImage: "play.rectangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focused(focused, equals: entry)
            .accessibilityIdentifier("browser.episode")
        case .title:
            EmptyView()
        }
    }
}

private extension SourceEntry {
    /// The title it opens, for an entry drawn as a poster.
    var poster: MetaPreview? {
        if case .title(let preview) = self { preview } else { nil }
    }

    var isPoster: Bool { poster != nil }
}
