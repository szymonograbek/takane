/// One folder of a source, for the screen that lists it. Each folder is its own screen with its own
/// store, so going back up is navigation.
enum SourceBrowserFeature: Feature {
    struct Dependencies: Sendable {
        let sources: any MediaSourceService
    }

    /// A folder of a source. A nil `id` is the source's root.
    struct Folder: Hashable, Sendable, CustomStringConvertible {
        let source: SourceID
        let id: SourceFolderID?

        var description: String { "\(source)/\(id?.description ?? "root")" }
    }

    enum State: Equatable, Sendable {
        case loading(Folder)
        /// Empty when the folder holds nothing to play.
        case loaded(Folder, [SourceEntry])
        case failed(Folder, SourceError)
    }

    enum Event: Sendable {
        case listed(Folder, Result<[SourceEntry], SourceError>)
        case retry
    }

    enum Effect: Equatable, Sendable {
        /// Start it when the store is created.
        case list(Folder)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state, event) {
        case (.loading(let folder), .listed(let answered, let result)) where answered == folder:
            state = switch result {
            case .success(let entries): .loaded(folder, entries)
            case .failure(let error): .failed(folder, error)
            }
            return []
        case (.failed(let folder, _), .retry):
            state = .loading(folder)
            return [.list(folder)]
        case (.loaded(let folder, let entries), .retry) where entries.isEmpty:
            state = .loading(folder)
            return [.list(folder)]
        case (.loading, .listed), (.loaded, .listed), (.failed, .listed), (.loading, .retry), (.loaded, .retry):
            return []
        }
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        switch effect {
        case .list(let folder):
            do throws(SourceError) {
                send(.listed(folder, .success(try await dependencies.sources.browse(folder.source, folder: folder.id))))
            } catch {
                send(.listed(folder, .failure(error)))
            }
        }
    }
}
