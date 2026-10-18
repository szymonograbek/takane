import Foundation
import Observation

/// Main-actor mirror of the core models the UI reads. Views read the typed state and call `send`.
@MainActor
@Observable
final class CoreStore {
    enum Status: Equatable {
        case starting
        case ready
        case failed(String)
    }

    struct EventRecord: Identifiable {
        let id = UUID()
        let date: Date
        let name: String
        let payload: JSONValue
    }

    private(set) var status: Status = .starting
    private(set) var ctx: CtxState?
    private(set) var continueWatching: ContinueWatchingState?
    private(set) var addonDetails: AddonDetailsState?
    private(set) var metaDetails: MetaDetailsState?
    private(set) var player: PlayerState?
    /// Most recent core events, newest last.
    private(set) var events: [EventRecord] = []

    @ObservationIgnored private var client: CoreClient?

    func start(storageDirectory: URL) async {
        guard status == .starting, client == nil else {
            Log.core.warning("start ignored, status is \(status)")
            return
        }
        do {
            let client = try await Task.detached(priority: .userInitiated) {
                try CoreClient.start(storageDirectory: storageDirectory)
            }.value
            self.client = client
            refresh(CoreField.allCases)
            status = .ready
            Log.core.info("core ready")
            Task { await listen(to: client.events) }
        } catch {
            Log.core.error("core failed to start: \(error)")
            status = .failed("\(error)")
        }
    }

    func send(_ action: CoreAction, to field: CoreField? = nil) {
        guard let client else {
            Log.core.error("send before core is ready: \(action)")
            return
        }
        do {
            try client.dispatch(action, to: field)
        } catch {
            Log.core.error("dispatch failed: \(error)")
        }
    }

    private func listen(to events: AsyncStream<CoreEvent>) async {
        for await event in events {
            switch event {
            case .newState(let fields):
                refresh(fields)
            case .core(let name, let payload):
                self.events.append(EventRecord(date: .now, name: name, payload: payload))
                if self.events.count > 100 {
                    self.events.removeFirst(self.events.count - 100)
                }
            }
        }
        Log.core.warning("core event stream ended")
    }

    private func refresh(_ fields: [CoreField]) {
        guard let client else { return }
        for field in fields {
            do {
                switch field {
                case .ctx: ctx = try client.state(field)
                case .continueWatchingPreview: continueWatching = try client.state(field)
                case .addonDetails: addonDetails = try client.state(field)
                case .metaDetails: metaDetails = try client.state(field)
                case .player: player = try client.state(field)
                }
            } catch {
                Log.core.error("refresh \(field.rawValue) failed: \(error)")
            }
        }
    }
}
