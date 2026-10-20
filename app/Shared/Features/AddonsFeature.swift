/// The installed add-ons, installing new ones by manifest URL and removing them.
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

    enum Removal: Equatable, Sendable {
        case idle
        case removing(ManifestURL)
        case failed(ManifestURL, AddonError)
    }

    struct State: Equatable, Sendable {
        var installed: [InstalledAddon] = []
        var install = Install.idle
        var removal = Removal.idle
    }

    enum Event: Sendable {
        case installedChanged([InstalledAddon])
        case install(ManifestURL)
        case installFinished(ManifestURL, Result<InstalledAddon, AddonError>)
        case uninstall(ManifestURL)
        case uninstallFinished(ManifestURL, Result<Void, AddonError>)
    }

    enum Effect: Equatable, Sendable {
        /// Start it once, when the store is created.
        case observeInstalled
        case install(ManifestURL)
        case uninstall(ManifestURL)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch event {
        case .uninstall, .uninstallFinished: reduceRemoval(&state, event)
        case .installedChanged, .install, .installFinished: reduceInstall(&state, event)
        }
    }

    private static func reduceRemoval(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state.removal, event) {
        case (.removing, .uninstall):
            return []
        case (.idle, .uninstall(let manifest)), (.failed, .uninstall(let manifest)):
            guard state.installed.contains(where: { $0.manifestURL == manifest && $0.isRemovable }) else { return [] }
            state.removal = .removing(manifest)
            return [.uninstall(manifest)]
        case (.removing(let pending), .uninstallFinished(let manifest, let result)) where pending == manifest:
            switch result {
            case .success: state.removal = .idle
            case .failure(let error): state.removal = .failed(manifest, error)
            }
            return []
        case (_, .uninstallFinished), (_, .installedChanged), (_, .install), (_, .installFinished):
            return []
        }
    }

    private static func reduceInstall(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state.install, event) {
        case (_, .installedChanged(let addons)):
            state.installed = addons
            return []
        case (.installing, .install):
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
        case (_, .installFinished), (_, .uninstall), (_, .uninstallFinished):
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
