/// One title's page: its metadata and videos, loaded from the add-ons.
enum DetailsFeature: Feature {
    struct Dependencies: Sendable {
        let catalog: any CatalogService
    }

    enum State: Equatable, Sendable {
        /// The preview the user picked shows while the full metadata loads.
        case loading(MetaPreview)
        case loaded(TitleDetails)
        case failed(MetaPreview, DetailsError)
    }

    enum Event: Sendable {
        case loaded(MediaID, Result<TitleDetails, DetailsError>)
        case retry
    }

    enum Effect: Equatable, Sendable {
        /// Start it when the store is created.
        case load(MetaPreview)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state, event) {
        case (.loading(let preview), .loaded(let media, let result)) where media == preview.media:
            switch result {
            case .success(let details): state = .loaded(details)
            case .failure(let error): state = .failed(preview, error)
            }
            return []
        case (.failed(let preview, _), .retry):
            state = .loading(preview)
            return [.load(preview)]
        case (_, .loaded), (.loading, .retry), (.loaded, .retry):
            return []
        }
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        switch effect {
        case .load(let preview):
            do {
                let details = try await dependencies.catalog.details(preview.media, type: preview.type)
                send(.loaded(preview.media, .success(details)))
            } catch {
                send(.loaded(preview.media, .failure(error)))
            }
        }
    }
}

extension DetailsFeature.State {
    var preview: MetaPreview {
        switch self {
        case .loading(let preview), .failed(let preview, _): preview
        case .loaded(let details): details.preview
        }
    }

    var details: TitleDetails? {
        if case .loaded(let details) = self { details } else { nil }
    }
}
