/// The installed add-ons, installing new ones by manifest URL, removing, ordering and switching them
/// on or off on this device.
enum AddonsFeature: Feature {
    struct Dependencies: Sendable {
        let addons: any AddonService
    }

    enum Install: Equatable, Sendable {
        case idle
        case installing(ManifestURL)
        case installed(InstalledAddon)
        case failed(ManifestURL, AddonError)
    }

    /// A change to the installed add-ons. One runs at a time.
    enum Change: Equatable, Sendable {
        case idle
        case removing(ManifestURL)
        case switching(ManifestURL, isEnabled: Bool)
        /// Moving one add-on, which lists them all in `order`.
        case ordering(ManifestURL, order: [ManifestURL])
        case failed(ManifestURL, AddonError)
    }

    /// Where an add-on moves in the list.
    enum Move: Sendable {
        case toTop, oneUp, oneDown
    }

    struct State: Equatable, Sendable {
        var installed: [InstalledAddon] = []
        var install = Install.idle
        var change = Change.idle
    }

    enum Event: Sendable {
        case installedChanged([InstalledAddon])
        /// The install screen opened. It starts clean unless an install is still in flight, which
        /// keeps reporting there.
        case installOpened
        case install(ManifestURL)
        case installFinished(ManifestURL, Result<InstalledAddon, AddonError>)
        case uninstall(ManifestURL)
        case uninstallFinished(ManifestURL, Result<Void, AddonError>)
        /// Switches the add-on on or off on this device only.
        case setEnabled(ManifestURL, Bool)
        case setEnabledFinished(ManifestURL, Bool, Result<Void, AddonError>)
        case move(ManifestURL, Move)
        case setOrderFinished([ManifestURL], Result<Void, AddonError>)
    }

    enum Effect: Equatable, Sendable {
        /// Start it once, when the store is created.
        case observeInstalled
        case install(ManifestURL)
        case uninstall(ManifestURL)
        case setEnabled(ManifestURL, Bool)
        case setOrder([ManifestURL])
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch event {
        case .uninstall, .uninstallFinished, .setEnabled, .setEnabledFinished, .move, .setOrderFinished: reduceChange(&state, event)
        case .installedChanged, .installOpened, .install, .installFinished: reduceInstall(&state, event)
        }
    }

    private static func reduceChange(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state.change, event) {
        case (.removing, .uninstall), (.removing, .setEnabled), (.removing, .move),
             (.switching, .uninstall), (.switching, .setEnabled), (.switching, .move),
             (.ordering, .uninstall), (.ordering, .setEnabled), (.ordering, .move):
            return []
        case (.idle, .uninstall(let manifest)), (.failed, .uninstall(let manifest)):
            guard state.installed.contains(where: { $0.manifestURL == manifest && $0.isRemovable }) else { return [] }
            state.change = .removing(manifest)
            return [.uninstall(manifest)]
        case (.idle, .setEnabled(let manifest, let isEnabled)), (.failed, .setEnabled(let manifest, let isEnabled)):
            guard state.installed.contains(where: { $0.manifestURL == manifest && $0.isEnabled != isEnabled }) else { return [] }
            state.change = .switching(manifest, isEnabled: isEnabled)
            return [.setEnabled(manifest, isEnabled)]
        case (.idle, .move(let manifest, let move)), (.failed, .move(let manifest, let move)):
            guard let order = state.installed.map(\.manifestURL).moving(manifest, move) else { return [] }
            state.change = .ordering(manifest, order: order)
            return [.setOrder(order)]
        case (.removing(let pending), .uninstallFinished(let manifest, let result)) where pending == manifest:
            state.change = Change(finished: manifest, result)
            return []
        case (.switching(let pending, let pendingIsEnabled), .setEnabledFinished(let manifest, let isEnabled, let result))
            where pending == manifest && pendingIsEnabled == isEnabled:
            state.change = Change(finished: manifest, result)
            return []
        case (.ordering(let manifest, let pending), .setOrderFinished(let order, let result)) where pending == order:
            state.change = Change(finished: manifest, result)
            return []
        case (_, .uninstallFinished), (_, .setEnabledFinished), (_, .setOrderFinished),
             (_, .installedChanged), (_, .installOpened), (_, .install), (_, .installFinished):
            return []
        }
    }

    private static func reduceInstall(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state.install, event) {
        case (_, .installedChanged(let addons)):
            state.installed = addons
            return []
        case (.installed, .installOpened), (.failed, .installOpened):
            state.install = .idle
            return []
        case (.idle, .installOpened), (.installing, .installOpened), (.installing, .install):
            return []
        case (.idle, .install(let manifest)), (.installed, .install(let manifest)), (.failed, .install(let manifest)):
            state.install = .installing(manifest)
            return [.install(manifest)]
        case (.installing(let pending), .installFinished(let manifest, let result)) where pending == manifest:
            switch result {
            case .success(let addon): state.install = .installed(addon)
            case .failure(let error): state.install = .failed(manifest, error)
            }
            return []
        case (_, .installFinished), (_, .uninstall), (_, .uninstallFinished), (_, .setEnabled), (_, .setEnabledFinished),
             (_, .move), (_, .setOrderFinished):
            return []
        }
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        switch effect {
        case .observeInstalled:
            for await addons in dependencies.addons.installed() {
                send(.installedChanged(addons))
            }
        case .install(let manifest):
            do {
                let addon = try await dependencies.addons.install(manifest)
                send(.installFinished(manifest, .success(addon)))
            } catch {
                send(.installFinished(manifest, .failure(error)))
            }
        case .uninstall(let manifest):
            do {
                try await dependencies.addons.uninstall(manifest)
                send(.uninstallFinished(manifest, .success(())))
            } catch {
                send(.uninstallFinished(manifest, .failure(error)))
            }
        case .setEnabled(let manifest, let isEnabled):
            do {
                try await dependencies.addons.setEnabled(manifest, isEnabled)
                send(.setEnabledFinished(manifest, isEnabled, .success(())))
            } catch {
                send(.setEnabledFinished(manifest, isEnabled, .failure(error)))
            }
        case .setOrder(let order):
            do {
                try await dependencies.addons.setOrder(order)
                send(.setOrderFinished(order, .success(())))
            } catch {
                send(.setOrderFinished(order, .failure(error)))
            }
        }
    }
}

extension [ManifestURL] {
    /// This order with `manifest` moved, or nil when it is not listed or `move` leaves it in place.
    func moving(_ manifest: ManifestURL, _ move: AddonsFeature.Move) -> [ManifestURL]? {
        guard let index = firstIndex(of: manifest) else { return nil }
        let target = switch move {
        case .toTop: startIndex
        case .oneUp: index - 1
        case .oneDown: index + 1
        }
        guard target != index, indices.contains(target) else { return nil }
        var order = self
        order.insert(order.remove(at: index), at: target)
        return order
    }
}

private extension AddonsFeature.Change {
    init(finished manifest: ManifestURL, _ result: Result<Void, AddonError>) {
        switch result {
        case .success: self = .idle
        case .failure(let error): self = .failed(manifest, error)
        }
    }
}

extension AddonsFeature.Install {
    var message: String? {
        switch self {
        case .idle: nil
        case .installing: "Installing…"
        case .installed(let addon): "Installed \(addon.name.rawValue)"
        case .failed(_, let error): error.message
        }
    }

    var isInstalling: Bool {
        if case .installing = self { true } else { false }
    }
}

extension AddonError {
    var message: String {
        switch self {
        case .manifestUnavailable(let reason): "The add-on's manifest could not be loaded: \(reason)"
        case .timedOut(let stage): "Timed out waiting for the \(stage)."
        case .rejected(let reason): "The request was refused: \(reason)"
        }
    }
}
