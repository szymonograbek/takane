/// The user's media sources: adding one, renaming it or changing its settings, setting what a
/// WebDAV source's folders hold, and removing it.
enum SourcesFeature: Feature {
    struct Dependencies: Sendable {
        let sources: any MediaSourceService
    }

    /// What a save is for. A save's answer names it, so an answer for another one is dropped.
    enum SaveTarget: Hashable, Sendable {
        case new(SourceKind, SourceEndpoint)
        case existing(SourceID)
    }

    /// Adding or editing a source. One runs at a time.
    enum Save: Equatable, Sendable {
        case idle
        case saving(SaveTarget)
        case saved(MediaSource)
        case failed(SaveTarget, SourceError)
    }

    /// Removing a source. One runs at a time.
    enum Removal: Equatable, Sendable {
        case idle
        case removing(SourceID)
        case failed(SourceID, SourceError)
    }

    /// A WebDAV source's library folders, for the page that sets their kinds. It lists one source's at a time.
    enum Folders: Equatable, Sendable {
        case idle
        case loading(SourceID)
        case loaded(SourceID, [FolderSuggestion])
        case failed(SourceID, SourceError)
    }

    /// Setting a library folder's kind. One runs at a time.
    enum KindChange: Equatable, Sendable {
        case idle
        case saving(SourceID, LibraryFolder)
        case failed(SourceID, LibraryFolder, SourceError)
    }

    struct State: Equatable, Sendable {
        var sources: [MediaSource] = []
        var save = Save.idle
        var removal = Removal.idle
        var folders = Folders.idle
        var kindChange = KindChange.idle
    }

    enum Event: Sendable {
        case sourcesChanged([MediaSource])
        /// The add or edit form opened. It starts clean unless a save is still in flight, which
        /// keeps reporting there.
        case formOpened
        case add(SourceKind, SourceLogin)
        case update(SourceID, SourceEdit)
        case saveFinished(SaveTarget, Result<MediaSource, SourceError>)
        case remove(SourceID)
        case removeFinished(SourceID, Result<Void, SourceError>)
        /// The page of a source's folders opened. It lists them again each time, so their suggested
        /// kinds follow the server.
        case foldersOpened(SourceID)
        case foldersListed(SourceID, Result<[FolderSuggestion], SourceError>)
        case setKind(FolderKind, LibraryFolder, SourceID)
        case kindSet(LibraryFolder, SourceID, Result<Void, SourceError>)
    }

    enum Effect: Equatable, Sendable {
        /// Start it once, when the store is created.
        case observeSources
        case add(SourceKind, SourceLogin)
        case update(SourceID, SourceEdit)
        case remove(SourceID)
        case listFolders(SourceID)
        case setKind(FolderKind, LibraryFolder, SourceID)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch event {
        case .sourcesChanged(let sources):
            state.sources = sources
            return []
        case .formOpened, .add, .update, .saveFinished: return reduceSave(&state, event)
        case .remove, .removeFinished: return reduceRemoval(&state, event)
        case .foldersOpened, .foldersListed: return reduceFolders(&state, event)
        case .setKind, .kindSet: return reduceKindChange(&state, event)
        }
    }

    private static func reduceSave(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state.save, event) {
        case (.saved, .formOpened), (.failed, .formOpened):
            state.save = .idle
            return []
        case (.idle, .formOpened), (.saving, .formOpened), (.saving, .add), (.saving, .update):
            return []
        case (.idle, .add(let kind, let login)), (.saved, .add(let kind, let login)), (.failed, .add(let kind, let login)):
            state.save = .saving(.new(kind, login.endpoint))
            return [.add(kind, login)]
        case (.idle, .update(let id, let edit)), (.saved, .update(let id, let edit)), (.failed, .update(let id, let edit)):
            guard state.sources.contains(where: { $0.id == id }) else { return [] }
            state.save = .saving(.existing(id))
            return [.update(id, edit)]
        case (.saving(let pending), .saveFinished(let target, let result)) where pending == target:
            switch result {
            case .success(let source): state.save = .saved(source)
            case .failure(let error): state.save = .failed(target, error)
            }
            return []
        case (_, .saveFinished), (_, .sourcesChanged), (_, .remove), (_, .removeFinished),
             (_, .foldersOpened), (_, .foldersListed), (_, .setKind), (_, .kindSet):
            return []
        }
    }

    private static func reduceRemoval(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state.removal, event) {
        case (.removing, .remove):
            return []
        case (.idle, .remove(let id)), (.failed, .remove(let id)):
            guard state.sources.contains(where: { $0.id == id }) else { return [] }
            state.removal = .removing(id)
            return [.remove(id)]
        case (.removing(let pending), .removeFinished(let id, let result)) where pending == id:
            switch result {
            case .success: state.removal = .idle
            case .failure(let error): state.removal = .failed(id, error)
            }
            return []
        case (_, .removeFinished), (_, .sourcesChanged), (_, .formOpened), (_, .add), (_, .update), (_, .saveFinished),
             (_, .foldersOpened), (_, .foldersListed), (_, .setKind), (_, .kindSet):
            return []
        }
    }

    private static func reduceFolders(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state.folders, event) {
        case (.loading(let pending), .foldersOpened(let id)) where pending == id:
            return []
        case (.idle, .foldersOpened(let id)), (.loading, .foldersOpened(let id)), (.loaded, .foldersOpened(let id)),
             (.failed, .foldersOpened(let id)):
            guard state.sources.contains(where: { $0.id == id && $0.kind == .webDAV }) else { return [] }
            state.folders = .loading(id)
            return [.listFolders(id)]
        case (.loading(let pending), .foldersListed(let id, let result)) where pending == id:
            switch result {
            case .success(let folders): state.folders = .loaded(id, folders)
            case .failure(let error): state.folders = .failed(id, error)
            }
            return []
        case (_, .foldersListed), (_, .sourcesChanged), (_, .formOpened), (_, .add), (_, .update), (_, .saveFinished),
             (_, .remove), (_, .removeFinished), (_, .setKind), (_, .kindSet):
            return []
        }
    }

    private static func reduceKindChange(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state.kindChange, event) {
        case (.saving, .setKind):
            return []
        case (.idle, .setKind(let kind, let folder, let id)), (.failed, .setKind(let kind, let folder, let id)):
            guard let source = state.sources.first(where: { $0.id == id }), source.kind == .webDAV else { return [] }
            guard source.folderKinds[folder] != kind else {
                state.kindChange = .idle
                return []
            }
            state.kindChange = .saving(id, folder)
            return [.setKind(kind, folder, id)]
        case (.saving(let pendingID, let pendingFolder), .kindSet(let folder, let id, let result)) where pendingID == id && pendingFolder == folder:
            switch result {
            case .success: state.kindChange = .idle
            case .failure(let error): state.kindChange = .failed(id, folder, error)
            }
            return []
        case (_, .kindSet), (_, .sourcesChanged), (_, .formOpened), (_, .add), (_, .update), (_, .saveFinished),
             (_, .remove), (_, .removeFinished), (_, .foldersOpened), (_, .foldersListed):
            return []
        }
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        switch effect {
        case .observeSources:
            for await sources in dependencies.sources.sources() {
                send(.sourcesChanged(sources))
            }
        case .add(let kind, let login):
            let target = SaveTarget.new(kind, login.endpoint)
            do {
                let source = try await dependencies.sources.add(kind, login)
                send(.saveFinished(target, .success(source)))
            } catch {
                send(.saveFinished(target, .failure(error)))
            }
        case .update(let id, let edit):
            do {
                let source = try await dependencies.sources.update(id, edit)
                send(.saveFinished(.existing(id), .success(source)))
            } catch {
                send(.saveFinished(.existing(id), .failure(error)))
            }
        case .remove(let id):
            do {
                try await dependencies.sources.remove(id)
                send(.removeFinished(id, .success(())))
            } catch {
                send(.removeFinished(id, .failure(error)))
            }
        case .listFolders(let id):
            do {
                send(.foldersListed(id, .success(try await dependencies.sources.libraryFolders(id))))
            } catch {
                send(.foldersListed(id, .failure(error)))
            }
        case .setKind(let kind, let folder, let id):
            do {
                try await dependencies.sources.setKind(kind, of: folder, on: id)
                send(.kindSet(folder, id, .success(())))
            } catch {
                send(.kindSet(folder, id, .failure(error)))
            }
        }
    }
}
