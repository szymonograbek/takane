/// The user's media sources: adding one, renaming it or changing its settings, and removing it.
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

    struct State: Equatable, Sendable {
        var sources: [MediaSource] = []
        var save = Save.idle
        var removal = Removal.idle
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
    }

    enum Effect: Equatable, Sendable {
        /// Start it once, when the store is created.
        case observeSources
        case add(SourceKind, SourceLogin)
        case update(SourceID, SourceEdit)
        case remove(SourceID)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch event {
        case .sourcesChanged(let sources):
            state.sources = sources
            return []
        case .formOpened, .add, .update, .saveFinished: return reduceSave(&state, event)
        case .remove, .removeFinished: return reduceRemoval(&state, event)
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
        case (_, .saveFinished), (_, .sourcesChanged), (_, .remove), (_, .removeFinished):
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
        case (_, .removeFinished), (_, .sourcesChanged), (_, .formOpened), (_, .add), (_, .update), (_, .saveFinished):
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
        }
    }
}
