import Foundation

/// Streams from the user's add-ons through core's `meta_details` model.
///
/// Core holds one `meta_details` selection, so a new lookup replaces the previous one and
/// finishes its stream.
struct CoreStreamService: StreamService {
    let runtime: CoreRuntime

    func streams(for item: PlayableID) -> AsyncStream<StreamResults> {
        let (results, continuation) = AsyncStream.makeStream(of: StreamResults.self, bufferingPolicy: .bufferingNewest(1))
        let streamPath = ResourcePath.stream(type: item.coreType, id: item.rawValue)
        // Subscribe before dispatching so no change is missed.
        let states = runtime.states(.metaDetails, as: MetaDetailsState.self)
        Log.core.info("loading streams for \(item.coreType)/\(item)")
        do {
            try runtime.dispatch(
                .load(.metaDetails(metaPath: .meta(type: item.coreType, id: item.media.rawValue), streamPath: streamPath)),
                to: .metaDetails
            )
        } catch {
            Log.core.error("stream lookup for \(item) rejected: \(error)")
            continuation.yield(StreamResults(item: item, sources: [], isComplete: true))
            continuation.finish()
            return results
        }
        let runtime = runtime
        let task = Task {
            let started = ContinuousClock.now
            var isSelected = false
            for await details in states {
                guard details.selected?.streamPath == streamPath else {
                    // Before our load lands the previous selection still shows; after, another lookup replaced ours.
                    if isSelected { break } else { continue }
                }
                isSelected = true
                let current = Self.results(for: item, from: details, addonNames: runtime.addonNames())
                continuation.yield(current)
                if current.isComplete {
                    Log.core.info("\(current.sources.count) addon responses for \(item) in \(ContinuousClock.now - started)")
                    break
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return results
    }

    private static func results(for item: PlayableID, from details: MetaDetailsState, addonNames: [URL: String]) -> StreamResults {
        // Core's player model needs the item's metadata request to record progress against it.
        let metaRequest = details.metaItems.first { $0.content?.readyContent != nil }?.request
        let sources = details.streams.compactMap { loadable -> StreamSource? in
            guard let addon = ManifestURL(loadable.request.base) else { return nil }
            let candidates: Remote<[StreamCandidate], StreamSourceError>
            switch loadable.content {
            case .none, .loading:
                candidates = .loading
            case .ready(let streams):
                candidates = .loaded(streams.enumerated().map { index, stream in
                    candidate(stream, id: StreamCandidate.ID(addon: addon, index: index), item: item,
                              streamRequest: loadable.request, metaRequest: metaRequest)
                })
            case .failed(let error):
                candidates = .failed(.addonFailed(reason: error.compactDescription))
            }
            let name = addonNames[addon.url] ?? addon.url.host() ?? "?"
            return StreamSource(addon: addon, addonName: name, candidates: candidates)
        }
        let isComplete = sources.allSatisfy(\.candidates.isSettled)
            && details.metaItems.allSatisfy { $0.content?.isSettled ?? false }
        return StreamResults(item: item, sources: sources, isComplete: isComplete)
    }

    private static func candidate(
        _ stream: Stream,
        id: StreamCandidate.ID,
        item: PlayableID,
        streamRequest: ResourceRequest,
        metaRequest: ResourceRequest?
    ) -> StreamCandidate {
        let playability: Playability = switch stream.source {
        case .url(let url): .playable(PlaybackSource(url: url, headers: stream.requestHeaders))
        case .unsupported(let kind): .unsupported(kind: kind)
        }
        // The subtitles path makes core's player model ask subtitle add-ons for this item.
        var selection: [String: JSONValue] = [
            "stream": stream.raw,
            "streamRequest": streamRequest.json,
            "subtitlesPath": ResourcePath.subtitles(type: item.coreType, id: item.rawValue).json,
        ]
        selection["metaRequest"] = metaRequest?.json
        return StreamCandidate(
            id: id,
            item: item,
            name: stream.name,
            description: stream.description,
            filename: stream.filename,
            playability: playability,
            tracking: TrackingToken(payload: .object(selection))
        )
    }
}

extension PlayableID {
    /// Core's resource type for the item.
    var coreType: String {
        switch self {
        case .movie: "movie"
        case .episode: "series"
        }
    }
}
