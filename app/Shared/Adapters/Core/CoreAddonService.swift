/// Add-ons as core's profile holds them.
struct CoreAddonService: AddonService {
    let runtime: CoreRuntime

    func installed() -> AsyncStream<[InstalledAddon]> {
        runtime.observe(.ctx, as: CtxState.self) { $0.profile.addons.compactMap(\.installed) }
    }

    func install(_ manifest: ManifestURL) async throws(AddonError) -> InstalledAddon {
        if let addon = try installedAddon(manifest) {
            Log.core.info("addon already installed: \(addon.name) \(addon.version)")
            return addon
        }
        Log.core.info("installing addon from \(manifest)")
        let url = manifest.url
        let descriptor: Addon
        do {
            descriptor = try await runtime.request(
                .load(.addonDetails(transportURL: url)), to: .addonDetails, observing: .addonDetails,
                as: AddonDetailsState.self, timeout: .seconds(30)
            ) { details -> Probe<Addon, AddonError> in
                guard let remote = details.remoteAddon, remote.transportUrl == url else { return .pending }
                switch remote.content {
                case .loading: return .pending
                case .ready(let addon): return .done(addon)
                case .failed(let error): return .failed(.manifestUnavailable(reason: error.compactDescription))
                }
            }
        } catch {
            throw Self.addonError(error, stage: "addon manifest")
        }
        Log.core.info("manifest loaded: \(descriptor.manifest.id) \(descriptor.manifest.name) \(descriptor.manifest.version)")
        do {
            return try await runtime.request(
                .ctx(.installAddon(descriptor: descriptor.descriptor)), to: nil, observing: .ctx,
                as: CtxState.self, timeout: .seconds(10)
            ) { ctx -> Probe<InstalledAddon, AddonError> in
                ctx.profile.addons.lazy.compactMap(\.installed).first { $0.manifestURL == manifest }.map(Probe.done) ?? .pending
            }
        } catch {
            throw Self.addonError(error, stage: "addon installed")
        }
    }

    func uninstall(_ manifest: ManifestURL) async throws(AddonError) {
        let profile: Profile
        do {
            profile = try runtime.state(.ctx, as: CtxState.self).profile
        } catch {
            throw .rejected(reason: "\(error)")
        }
        guard let addon = profile.addons.first(where: { $0.transportUrl == manifest.url }) else { return }
        Log.core.info("uninstalling \(addon.manifest.name)")
        do {
            try await runtime.request(
                .ctx(.uninstallAddon(descriptor: addon.descriptor)), to: nil, observing: .ctx,
                as: CtxState.self, timeout: .seconds(10)
            ) { ctx -> Probe<Void, AddonError> in
                ctx.profile.addons.contains { $0.transportUrl == manifest.url } ? .pending : .done(())
            }
        } catch {
            throw Self.addonError(error, stage: "add-on removal")
        }
    }

    private func installedAddon(_ manifest: ManifestURL) throws(AddonError) -> InstalledAddon? {
        do {
            let ctx = try runtime.state(.ctx, as: CtxState.self)
            return ctx.profile.addons.lazy.compactMap(\.installed).first { $0.manifestURL == manifest }
        } catch {
            throw .rejected(reason: "\(error)")
        }
    }

    private static func addonError(_ error: CoreRequestError<AddonError>, stage: String) -> AddonError {
        switch error {
        case .rejected(let error): .rejected(reason: "\(error)")
        case .timedOut: .timedOut(stage: stage)
        case .failed(let error): error
        }
    }
}

private extension Addon {
    var installed: InstalledAddon? {
        guard let manifestURL = ManifestURL(transportUrl) else {
            Log.core.warning("addon \(manifest.id) has an unsupported transport URL")
            return nil
        }
        return InstalledAddon(
            manifestURL: manifestURL, name: manifest.name, version: manifest.version, isRemovable: !(flags?.isProtected ?? false)
        )
    }
}
