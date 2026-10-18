import Foundation

/// Multi-step core interactions shared by the UI and the smoke test.
struct WorkflowError: Error, CustomStringConvertible {
    let description: String
}

/// Streams one addon returned for one request.
struct StreamGroup: Identifiable, Sendable {
    let request: ResourceRequest
    let addonName: String
    let streams: [Stream]

    var id: URL { request.base }
}

extension CoreStore {
    /// Fetches the addon's manifest through core and installs it. Returns the installed addon.
    func installAddon(from transportURL: URL) async throws -> Addon {
        if let installed = installedAddon(transportURL) {
            Log.core.info("addon already installed: \(installed.manifest.name) \(installed.manifest.version)")
            return installed
        }
        Log.core.info("installing addon from \(transportURL.absoluteString)")
        send(.load(.addonDetails(transportURL: transportURL)), to: .addonDetails)
        let addon = try await waitUntil("addon manifest", timeout: .seconds(30)) { () throws -> Addon? in
            guard let remote = addonDetails?.remoteAddon, remote.transportUrl == transportURL else { return nil }
            switch remote.content {
            case .loading: return nil
            case .ready(let addon): return addon
            case .failed(let error): throw WorkflowError(description: "manifest failed: \(error.compactDescription)")
            }
        }
        Log.core.info("manifest loaded: \(addon.manifest.id) \(addon.manifest.name) \(addon.manifest.version)")
        send(.ctx(.installAddon(descriptor: addon.descriptor)))
        return try await waitUntil("addon installed", timeout: .seconds(10)) { installedAddon(transportURL) }
    }

    func installedAddon(_ transportURL: URL) -> Addon? {
        ctx?.profile.addons.first { $0.transportUrl == transportURL }
    }

    /// Loads metadata and streams for `type`/`id` (e.g. `movie`/`tt0111161`, `series`/`tt0944947:1:1`)
    /// and waits until every addon has answered.
    func loadStreams(type: String, id: String) async throws -> [StreamGroup] {
        // Series stream ids carry season and episode; the meta id is the show's id.
        let metaID = id.split(separator: ":").first.map(String.init) ?? id
        Log.core.info("loading streams for \(type)/\(id)")
        send(.load(.metaDetails(metaPath: .meta(type: type, id: metaID), streamPath: .stream(type: type, id: id))), to: .metaDetails)
        let started = ContinuousClock.now
        let streams = try await waitUntil("streams for \(id)", timeout: .seconds(60)) { () -> [ResourceLoadable<[Stream]>]? in
            guard let details = metaDetails,
                  let first = details.streams.first,
                  first.request.path.id == id,
                  details.streams.allSatisfy({ $0.content.map { if case .loading = $0 { false } else { true } } ?? false })
            else { return nil }
            return details.streams
        }
        Log.core.info("\(streams.count) addon responses for \(id) in \(ContinuousClock.now - started)")
        return streams.compactMap { loadable in
            let addonName = ctx?.profile.addons.first { $0.transportUrl == loadable.request.base }?.manifest.name
                ?? loadable.request.base.host() ?? "?"
            switch loadable.content {
            case .ready(let streams):
                let playable = streams.filter { $0.playableURL != nil }.count
                Log.core.info("\(addonName): \(streams.count) streams, \(playable) playable")
                return StreamGroup(request: loadable.request, addonName: addonName, streams: streams)
            case .failed(let error):
                Log.core.warning("\(addonName): \(error.compactDescription)")
                return nil
            case .loading, nil:
                return nil
            }
        }
    }

    /// The request for the item's metadata, which core's player model needs to record progress.
    var metaRequest: ResourceRequest? {
        metaDetails?.metaItems.first { $0.content?.readyContent != nil }?.request
    }

    /// Polls `probe` until it returns a value. Core state arrives asynchronously via events.
    func waitUntil<Value>(
        _ what: String,
        timeout: Duration,
        _ probe: () throws -> Value?
    ) async throws -> Value {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let value = try probe() { return value }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw WorkflowError(description: "timed out after \(timeout) waiting for \(what)")
    }
}
