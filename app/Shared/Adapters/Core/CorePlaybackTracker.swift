import Foundation

/// Reports playback to core's player model, which records progress, watched state and continue watching.
/// Core copies progress into the library on pause, unload and every 180 s. In-process add-ons hear
/// about their own streams through `reports`.
struct CorePlaybackTracker: PlaybackTracker {
    let runtime: CoreRuntime
    let links: any CorePlaybackLinks
    let reports: any CorePlaybackReports

    #if os(tvOS)
    private static let device = "tvos"
    #else
    private static let device = "macos"
    #endif

    func begin(_ candidate: StreamCandidate) {
        send(.load(.player(selection: candidate.tracking.payload.rawValue)))
        reports.playback(Self.placeholder(of: candidate).map(InProcessPlayback.began) ?? .stopped)
    }

    func progress(_ position: Duration, of duration: Duration) {
        send(.player(.timeChanged(timeMs: position.milliseconds, durationMs: duration.milliseconds, device: Self.device)))
        reports.playback(.position(position))
    }

    func seek(to position: Duration, of duration: Duration) {
        send(.player(.seek(timeMs: position.milliseconds, durationMs: duration.milliseconds, device: Self.device)))
        reports.playback(.position(position))
    }

    func paused(_ paused: Bool) {
        send(.player(.pausedChanged(paused: paused)))
        reports.playback(.paused(paused))
    }

    func ended() {
        send(.player(.ended))
        reports.playback(.stopped)
    }

    func movedToNext() {
        send(.player(.nextVideo))
    }

    func stop() {
        send(.unload)
        reports.playback(.stopped)
    }

    /// Core loads the selection's meta item and finds the next video in it, then asks the selected
    /// stream's add-on for that video's streams and picks the one in the same binge group.
    func title(of candidate: StreamCandidate) -> AsyncStream<PlayingTitle?> {
        let (results, continuation) = AsyncStream.makeStream(of: PlayingTitle?.self, bufferingPolicy: .bufferingNewest(1))
        let links = links
        let answers = runtime.observe(.player, as: PlayerState.self) { Self.answer(for: candidate, in: $0, links: links) }
        let task = Task {
            var isSelected = false
            for await answer in answers {
                guard case .selected(let title) = answer else {
                    // Before the load lands another selection still shows; after, another candidate replaced this one.
                    if isSelected { break } else { continue }
                }
                isSelected = true
                continuation.yield(title)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return results
    }

    /// Core saves it once its player model has loaded the title's metadata; a choice made before then
    /// is dropped.
    func remember(_ choices: TrackChoices) {
        var state: StreamItemState
        do {
            state = try runtime.state(.player, as: PlayerState.self).streamState ?? StreamItemState()
        } catch {
            Log.core.error("reading the stream state failed: \(error)")
            return
        }
        state.choices = choices
        send(.player(.streamStateChanged(state)))
    }

    /// Core's player model reads the saved state once it has loaded the title's metadata. For another
    /// video of the title it carries over the speed, and the tracks when the streams share a binge group.
    func remembered(for candidate: StreamCandidate, playing source: PlaybackSource) -> AsyncStream<TrackChoices> {
        let (results, continuation) = AsyncStream.makeStream(of: TrackChoices.self, bufferingPolicy: .bufferingNewest(1))
        let links = links
        let selections = runtime.observe(.player, as: PlayerState.self) { player -> RememberedSelection in
            player.plays(candidate, from: source, links: links) ? .current(player.streamState?.choices) : .other
        }
        let task = Task {
            var isSelected = false
            loop: for await selection in selections {
                switch selection {
                case .other where isSelected:
                    // Another candidate replaced this one.
                    break loop
                case .other:
                    // The tracker's load has not landed yet.
                    continue
                case .current(nil):
                    isSelected = true
                case .current(let choices?):
                    continuation.yield(choices)
                    break loop
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return results
    }

    private func send(_ action: CoreAction) {
        runtime.dispatchLogged(action, to: .player)
    }

    /// The stream's URL as its add-on gave it, which `CoreStreamResults` keeps in the tracking token,
    /// when an in-process add-on gave it.
    private static func placeholder(of candidate: StreamCandidate) -> InProcessURL? {
        guard case .object(let selection) = candidate.tracking.payload.rawValue, case .object(let stream)? = selection["stream"],
              case .string(let text)? = stream["url"], let url = URL(string: text)
        else { return nil }
        return InProcessURL(url)
    }
}

private extension CorePlaybackTracker {
    /// What one state of core's player model says about a candidate's title.
    enum Answer: Equatable, Sendable {
        case otherSelection
        case selected(PlayingTitle?)
    }

    static func answer(for candidate: StreamCandidate, in player: PlayerState, links: any CorePlaybackLinks) -> Answer {
        guard let selected = player.selected, let source = candidate.source,
              links.playability(of: selected.stream) == .playable(source), selected.streamRequest?.path.id == candidate.item.rawValue
        else { return .otherSelection }
        guard let show = player.metaItem?.content?.readyContent else { return .selected(nil) }
        let backdrop = show.background.flatMap(URL.init(string:))
        let next = player.nextVideo.flatMap { video in
            PlayableID(video.id).map { id in
                UpNext(
                    video: id, show: Redacted(show.name), title: Redacted(video.title),
                    thumbnail: video.thumbnail.flatMap(URL.init(string:)), backdrop: backdrop,
                    stream: nextCandidate(for: id, in: player, links: links)
                )
            }
        }
        return .selected(PlayingTitle(
            name: Redacted(show.name), description: show.description.map(Redacted.init), backdrop: backdrop,
            videos: show.videos.compactMap { $0.video(watched: player.watchedVideos) }, next: next
        ))
    }

    /// Core's next stream as a candidate that plays here, tracked against the same meta item.
    static func nextCandidate(for video: PlayableID, in player: PlayerState, links: any CorePlaybackLinks) -> StreamCandidate? {
        guard let stream = player.nextStream, let streams = player.nextStreams,
              let addon = ManifestURL(streams.request.base),
              let index = streams.content?.readyContent?.firstIndex(where: { $0.raw == stream.raw })
        else { return nil }
        let candidate = CoreStreamResults(links: links).candidate(
            stream, id: StreamCandidate.ID(addon: addon, index: index), item: video,
            streamRequest: streams.request, metaRequest: player.selected?.metaRequest
        )
        return candidate.source == nil ? nil : candidate
    }
}

/// Whether core's player has the candidate selected, and what it saved for it.
private enum RememberedSelection: Equatable, Sendable {
    case other
    case current(TrackChoices?)
}

private extension Duration {
    var milliseconds: UInt64 {
        UInt64(max(0, self / .milliseconds(1)))
    }
}
