import Foundation

/// Streams from the user's add-ons through core's `meta_details` model.
///
/// Core holds one `meta_details` selection, so a new lookup replaces the previous one and
/// finishes its stream.
struct CoreStreamService: StreamService {
    let runtime: CoreRuntime
    let links: any CorePlaybackLinks

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
        let links = links
        let task = Task {
            let started = ContinuousClock.now
            var isSelected = false
            for await details in states {
                guard details.selected?.streamPath == streamPath else {
                    // Before our load lands the previous selection still shows; after, another lookup replaced ours.
                    if isSelected { break } else { continue }
                }
                isSelected = true
                let current = CoreStreamResults(links: links).results(for: item, from: details, addonNames: runtime.addonNames())
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
}
