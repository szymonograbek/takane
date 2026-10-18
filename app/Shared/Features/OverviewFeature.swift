/// The account and continue watching, as the library reports them.
enum OverviewFeature: Feature {
    struct Dependencies: Sendable {
        let library: any LibraryService
    }

    struct State: Equatable, Sendable {
        var account = Account.anonymous
        var continueWatching: [ContinueWatchingItem] = []
    }

    enum Event: Sendable {
        case accountChanged(Account)
        case continueWatchingChanged([ContinueWatchingItem])
    }

    enum Effect: Equatable, Sendable {
        /// Start both once, when the store is created.
        case observeAccount
        case observeContinueWatching
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch event {
        case .accountChanged(let account): state.account = account
        case .continueWatchingChanged(let items): state.continueWatching = items
        }
        return []
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        switch effect {
        case .observeAccount:
            for await account in dependencies.library.account() {
                send(.accountChanged(account))
            }
        case .observeContinueWatching:
            for await items in dependencies.library.continueWatching() {
                send(.continueWatchingChanged(items))
            }
        }
    }
}

extension Account {
    var label: String {
        switch self {
        case .anonymous: "anonymous"
        case .signedIn(let email): email
        }
    }
}

extension ContinueWatchingItem {
    var progressLabel: String {
        "\(name) · \(offset.components.seconds)s / \(duration.components.seconds)s"
    }
}
