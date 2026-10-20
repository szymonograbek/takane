/// Sharing the logs with another device on the network while the screen that shows the link is up.
enum LogSharingFeature: Feature {
    struct Dependencies: Sendable {
        let sharing: any LogSharing
    }

    enum State: Equatable, Sendable {
        case idle
        case starting(LogWindow)
        case sharing(LogLink, LogWindow)
        case failed(LogWindow, LogSharingError)
    }

    enum Event: Sendable {
        case appeared
        case select(LogWindow)
        case shareFinished(LogWindow, Result<LogLink, LogSharingError>)
        case retry
        case disappeared
    }

    enum Effect: Equatable, Sendable {
        case share(LogWindow)
        case stop
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state, event) {
        case (.idle, .appeared):
            state = .starting(.default)
            return [.share(.default)]
        case (.starting, .select(let window)), (.failed, .select(let window)):
            state = .starting(window)
            return [.share(window)]
        // The link stays the same, so it stays on screen while the new window is shared.
        case (.sharing(let link, _), .select(let window)):
            state = .sharing(link, window)
            return [.share(window)]
        case (.failed(let window, _), .retry):
            state = .starting(window)
            return [.share(window)]
        case (.starting(let current), .shareFinished(let window, let result)) where window == current,
             (.sharing(_, let current), .shareFinished(let window, let result)) where window == current:
            switch result {
            case .success(let link): state = .sharing(link, window)
            case .failure(let error): state = .failed(window, error)
            }
            return []
        case (.starting, .disappeared), (.sharing, .disappeared), (.failed, .disappeared):
            state = .idle
            return [.stop]
        case (.starting, .appeared), (.sharing, .appeared), (.failed, .appeared),
             (.idle, .select), (.idle, .shareFinished), (.starting, .shareFinished), (.sharing, .shareFinished),
             (.failed, .shareFinished), (.idle, .retry), (.starting, .retry), (.sharing, .retry),
             (.idle, .disappeared):
            return []
        }
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        switch effect {
        case .share(let window):
            do {
                send(.shareFinished(window, .success(try await dependencies.sharing.share(window))))
            } catch {
                send(.shareFinished(window, .failure(error)))
            }
        case .stop:
            await dependencies.sharing.stop()
        }
    }
}

extension LogSharingFeature.State {
    var window: LogWindow? {
        switch self {
        case .idle: nil
        case .starting(let window), .sharing(_, let window), .failed(let window, _): window
        }
    }
}

extension LogSharingError {
    var message: String {
        switch self {
        case .noLocalNetwork: "Connect this device to a network to share its logs."
        case .listenerFailed(let reason): "The logs could not be shared (\(reason))."
        }
    }
}
