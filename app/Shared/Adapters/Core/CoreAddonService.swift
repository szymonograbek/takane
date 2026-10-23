import Foundation

/// Add-ons as core's profile holds them, each on or off on this device as the bridge holds it.
struct CoreAddonService: AddonService {
    let runtime: CoreRuntime

    func installed() -> AsyncStream<[InstalledAddon]> {
        runtime.observe(.ctx, as: CtxState.self) { $0.installedAddons }
    }

    func install(_ manifest: ManifestURL) async throws(AddonError) -> InstalledAddon {
        if let addon = try installedAddon(manifest) {
            Log.core.info("addon already installed: \(addon.name) \(addon.version)")
            return addon
        }
        Log.core.info("installing addon from \(manifest)")
        let url = manifest.url.rawValue
        let descriptor: Addon
        do {
            descriptor = try await runtime.request(
                .core(.load(.addonDetails(transportURL: url)), to: .addonDetails), observing: .addonDetails,
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
                .core(.ctx(.installAddon(descriptor: descriptor.descriptor)), to: nil), observing: .ctx,
                as: CtxState.self, timeout: .seconds(10)
            ) { ctx -> Probe<InstalledAddon, AddonError> in
                ctx.installedAddons.first { $0.manifestURL == manifest }.map(Probe.done) ?? .pending
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
        guard let addon = profile.addons.first(where: { $0.transportUrl == manifest.url.rawValue }) else { return }
        Log.core.info("uninstalling \(addon.manifest.name)")
        do {
            try await runtime.request(
                .core(.ctx(.uninstallAddon(descriptor: addon.descriptor)), to: nil), observing: .ctx,
                as: CtxState.self, timeout: .seconds(10)
            ) { ctx -> Probe<Void, AddonError> in
                ctx.profile.addons.contains { $0.transportUrl == manifest.url.rawValue } ? .pending : .done(())
            }
        } catch {
            throw Self.addonError(error, stage: "add-on removal")
        }
    }

    func setEnabled(_ manifest: ManifestURL, _ isEnabled: Bool) async throws(AddonError) {
        let url = manifest.url.rawValue
        Log.core.info("switching \(manifest) \(isEnabled ? "on" : "off") on this device")
        do {
            try await runtime.request(
                .bridge(.setAddonEnabled(transportURL: url, isEnabled: isEnabled)), observing: .ctx,
                as: CtxState.self, timeout: .seconds(10)
            ) { ctx -> Probe<Void, AddonError> in
                ctx.disabledAddons.contains(url) == isEnabled ? .pending : .done(())
            }
        } catch {
            throw Self.addonError(error, stage: "add-on switch")
        }
    }

    func setOrder(_ order: [ManifestURL]) async throws(AddonError) {
        let urls = order.map(\.url.rawValue)
        Log.core.info("ordering \(order.count) add-ons")
        do {
            try await runtime.request(
                .bridge(.setAddonOrder(transportURLs: urls)), observing: .ctx, as: CtxState.self, timeout: .seconds(10)
            ) { ctx -> Probe<Void, AddonError> in
                ctx.profile.addons.map(\.transportUrl) == urls ? .done(()) : .pending
            }
        } catch {
            throw Self.addonError(error, stage: "add-on order")
        }
    }

    private func installedAddon(_ manifest: ManifestURL) throws(AddonError) -> InstalledAddon? {
        do {
            let ctx = try runtime.state(.ctx, as: CtxState.self)
            return ctx.installedAddons.first { $0.manifestURL == manifest }
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

private extension CtxState {
    var installedAddons: [InstalledAddon] {
        profile.addons.compactMap { addon in
            guard let manifestURL = ManifestURL(addon.transportUrl) else {
                Log.core.warning("addon \(addon.manifest.id) has an unsupported transport URL")
                return nil
            }
            return InstalledAddon(
                manifestURL: manifestURL, name: addon.manifest.name, version: addon.manifest.version,
                isRemovable: !(addon.flags?.isProtected ?? false), isEnabled: !disabledAddons.contains(addon.transportUrl)
            )
        }
    }
}

extension CoreRuntime {
    /// Installed add-ons' names by transport URL, for labelling their answers.
    func addonNames() -> [URL: Redacted<String>] {
        do {
            let ctx = try state(.ctx, as: CtxState.self)
            return Dictionary(ctx.profile.addons.map { ($0.transportUrl, $0.manifest.name) }) { first, _ in first }
        } catch {
            Log.core.error("reading addon names failed: \(error)")
            return [:]
        }
    }
}
