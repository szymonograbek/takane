/// One title's page: its metadata and videos, loaded from the add-ons, the watched marks on them,
/// whether the title is in the library and the viewer's rating of it.
enum DetailsFeature: Feature {
    struct Dependencies: Sendable {
        let catalog: any CatalogService
        let library: any LibraryService
    }

    enum State: Equatable, Sendable {
        /// The preview the user picked shows while the full metadata loads.
        case loading(MetaPreview)
        case loaded(TitleDetails)
        case failed(MetaPreview, DetailsError)
    }

    enum Event: Sendable {
        case loaded(MediaID, Result<TitleDetails, DetailsError>)
        /// The loaded details changed, such as a video marked watched here or in the player.
        case changed(TitleDetails)
        case retry
        case setWatched(WatchedTarget, Bool)
        case setInLibrary(Bool)
        /// Nil clears the rating.
        case rate(TitleRating?)
    }

    enum Effect: Equatable, Sendable {
        /// Start it when the store is created. Once loaded, it follows the details' changes.
        case load(MetaPreview)
        case setWatched(WatchedTarget, Bool)
        case setInLibrary(MetaPreview, Bool)
        case rate(MediaID, TitleRating?)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state, event) {
        case (.loading(let preview), .loaded(let media, let result)) where media == preview.media:
            switch result {
            case .success(let details): state = .loaded(details)
            case .failure(let error): state = .failed(preview, error)
            }
            return []
        case (.loaded(let current), .changed(let details)) where details.preview.media == current.preview.media:
            state = .loaded(details)
            return []
        case (.failed(let preview, _), .retry):
            state = .loading(preview)
            return [.load(preview)]
        case (.loaded(let details), .setWatched(let target, let isWatched)) where target.media == details.preview.media:
            return [.setWatched(target, isWatched)]
        case (.loaded(let details), .setInLibrary(let isInLibrary)):
            return [.setInLibrary(details.preview, isInLibrary)]
        case (.loaded(let details), .rate(let rating)) where details.rating != .unavailable:
            return [.rate(details.preview.media, rating)]
        case (_, .loaded), (_, .changed), (.loading, .retry), (.loaded, .retry), (_, .setWatched),
             (.loading, .setInLibrary), (.failed, .setInLibrary), (_, .rate):
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
                return
            }
            for await details in dependencies.catalog.detailsChanges(preview.media, type: preview.type) {
                send(.changed(details))
            }
        case .setWatched(let target, let isWatched):
            do {
                try dependencies.library.setWatched(target, isWatched)
            } catch {
                Log.features.error("marking \(target) as watched: \(isWatched) failed: \(error)")
            }
        case .setInLibrary(let title, let isInLibrary):
            dependencies.library.setInLibrary(title, isInLibrary)
        case .rate(let media, let rating):
            do {
                try dependencies.library.rate(media, rating)
            } catch {
                Log.features.error("rating \(media) as \(String(describing: rating)) failed: \(error)")
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
