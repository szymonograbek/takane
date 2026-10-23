import Foundation

/// The add-ons' answers in core's `meta_details` state, as stream results whose tracking tokens
/// hold the selection core's player model loads. Each candidate plays what `links` resolves its
/// stream's URL to.
struct CoreStreamResults {
    let links: any CorePlaybackLinks

    func results(for item: PlayableID, from details: MetaDetailsState, addonNames: [URL: Redacted<String>]) -> StreamResults {
        // Core's player model loads the item's metadata from this request and records progress against
        // it, so a stream picked while the metadata loads, or after it failed, needs it too.
        let metaRequest = (details.metaItems.first { $0.content?.readyContent != nil } ?? details.metaItems.first)?.request
        // An add-on can both embed streams in its metadata and answer the stream request; it gets one
        // source holding both, the embedded streams first.
        var responses: [(addon: ManifestURL, loadables: [ResourceLoadable<[Stream]>])] = []
        for loadable in details.metaStreams + details.streams {
            guard let addon = ManifestURL(loadable.request.base) else { continue }
            if let index = responses.firstIndex(where: { $0.addon == addon }) {
                responses[index].loadables.append(loadable)
            } else {
                responses.append((addon, [loadable]))
            }
        }
        let sources = responses.map { addon, loadables in
            StreamSource(
                addon: addon,
                addonName: addonNames[addon.url.rawValue] ?? Redacted(addon.url.rawValue.host() ?? "?"),
                candidates: candidates(from: loadables, addon: addon, item: item, metaRequest: metaRequest)
            )
        }
        let isComplete = sources.allSatisfy(\.candidates.isSettled)
            && details.metaItems.allSatisfy { $0.content?.isSettled ?? false }
        return StreamResults(item: item, sources: sources, isComplete: isComplete)
    }

    /// Loading until each of the add-on's responses settles, then the streams of those that are ready;
    /// failed only when none is.
    private func candidates(
        from loadables: [ResourceLoadable<[Stream]>],
        addon: ManifestURL,
        item: PlayableID,
        metaRequest: ResourceRequest?
    ) -> Remote<[StreamCandidate], StreamSourceError> {
        var candidates: [StreamCandidate] = []
        var failure: StreamSourceError?
        for loadable in loadables {
            switch loadable.content {
            case .none, .loading:
                return .loading
            case .ready(let streams):
                for stream in streams {
                    candidates.append(candidate(stream, id: StreamCandidate.ID(addon: addon, index: candidates.count), item: item,
                                                streamRequest: loadable.request, metaRequest: metaRequest))
                }
            case .failed(let error):
                failure = .addonFailed(reason: error.compactDescription)
            }
        }
        if let failure, candidates.isEmpty { return .failed(failure) }
        return .loaded(candidates)
    }

    /// `stream` as a candidate whose tracking token loads core's player model with it. The token
    /// keeps the stream as core has it, a placeholder URL included.
    func candidate(
        _ stream: Stream,
        id: StreamCandidate.ID,
        item: PlayableID,
        streamRequest: ResourceRequest,
        metaRequest: ResourceRequest?
    ) -> StreamCandidate {
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
            name: stream.name.map(Redacted.init),
            description: stream.description.map(Redacted.init),
            filename: stream.filename.map(Redacted.init),
            playability: links.playability(of: stream),
            tracking: TrackingToken(payload: Redacted(.object(selection)))
        )
    }
}

extension PlayableID {
    /// Core's resource type for the item.
    var coreType: String {
        switch self {
        case .movie: "movie"
        case .episode: "series"
        case .liveChannel: "tv"
        }
    }
}
