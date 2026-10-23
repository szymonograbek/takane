import SwiftUI

/// A WebDAV source's top-level folders, each showing what it holds and opening the list of kinds.
/// A folder shows the kind its videos suggest until the user picks one.
struct SourceFolderSettings: View {
    @Environment(AppContext.self) private var app
    let id: SourceID
    /// The folders arrive after the screen opens; focus then moves to the first one.
    @FocusState private var focused: LibraryFolder?
    /// Coming back from a folder's kinds shows the same list, without listing it again.
    @State private var hasListed = false

    var body: some View {
        let state = app.sources.state
        SettingsPage(title: "Folders") {
            SettingsSymbol(name: "folder")
        } rows: {
            switch state.folders {
            case .loaded(let listed, let suggestions) where listed == id && suggestions.isEmpty:
                SettingsSection(note: "This folder holds no folders with videos in them.") {
                    ValueRow(title: "Folders", value: "None")
                }
            case .loaded(let listed, let suggestions) where listed == id:
                SettingsSection(note: kindFailure(state.kindChange)?.message ?? Self.note) {
                    ForEach(suggestions, id: \.folder) { suggestion in
                        row(suggestion, chosen: state.sources.first { $0.id == id }?.folderKinds[suggestion.folder], saving: state.kindChange)
                    }
                }
            case .failed(let listed, let error) where listed == id:
                SettingsSection(note: error.message) {
                    Button("Try Again") { app.sources.send(.foldersOpened(id)) }
                        .accessibilityIdentifier("sourceFolders.retry")
                }
            case .idle, .loading, .loaded, .failed:
                ValueRow(title: "Folders", value: "Loading…")
                    .accessibilityIdentifier("sourceFolders.loading")
            }
        }
        .onAppear {
            guard !hasListed else { return }
            hasListed = true
            app.sources.send(.foldersOpened(id))
        }
        .onChange(of: first, initial: true) { _, first in
            if focused == nil { focused = first }
        }
    }

    private static let note = "Takane looks titles up by name only in Movies and Shows folders, so videos in Other Videos "
        + "keep their own names and details."

    private var first: LibraryFolder? {
        guard case .loaded(let listed, let suggestions) = app.sources.state.folders, listed == id else { return nil }
        return suggestions.first?.folder
    }

    private func row(_ suggestion: FolderSuggestion, chosen: FolderKind?, saving: SourcesFeature.KindChange) -> some View {
        let kind = chosen ?? suggestion.kind
        let name = suggestion.folder.name.rawValue
        let isSaving = saving == .saving(id, suggestion.folder)
        return NavigationLink {
            ChoiceList(
                title: name, symbol: "folder", choices: FolderKind.allCases.map { (name: $0.name, value: $0) }, selection: kind
            ) {
                app.sources.send(.setKind($0, suggestion.folder, id))
            }
        } label: {
            LabeledContent(name, value: isSaving ? "Saving…" : kind.name)
        }
        .focused($focused, equals: suggestion.folder)
        .accessibilityIdentifier("sourceFolders.row")
    }

    private func kindFailure(_ change: SourcesFeature.KindChange) -> SourceError? {
        if case .failed(let failed, _, let error) = change, failed == id { error } else { nil }
    }
}

private extension FolderKind {
    var name: String {
        switch self {
        case .movies: "Movies"
        case .shows: "Shows"
        case .otherVideos: "Other Videos"
        }
    }
}
