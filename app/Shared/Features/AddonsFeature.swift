/// The installed add-ons and installing new ones by manifest URL.
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

    struct State: Equatable, Sendable {
        var installed: [InstalledAddon] = []
        var install = Install.idle
    }

    enum Event: Sendable {
        case installedChanged([InstalledAddon])
        case install(ManifestURL)
        case installFinished(ManifestURL, Result<InstalledAddon, AddonError>)
    }

    enum Effect: Equatable, Sendable {
        /// Start it once, when the store is created.
        case observeInstalled
        case install(ManifestURL)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
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
        case (_, .installFinished):
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
        }
    }
}

extension AddonsFeature.Install {
    var message: String? {
        switch self {
        case .idle: nil
        case .installing: "Installing…"
        case .installed(let addon): "Installed \(addon.name)"
        case .failed(_, .manifestUnavailable(let reason)): "manifest failed: \(reason)"
        case .failed(_, .timedOut(let stage)): "timed out waiting for \(stage)"
        case .failed(_, .rejected(let reason)): "core rejected the request: \(reason)"
        }
    }

    var isInstalling: Bool {
        if case .installing = self { true } else { false }
    }
}
