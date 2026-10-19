import Foundation

/// Reports playback to core's player model, which records progress, watched state and continue watching.
/// Core copies progress into the library on pause, unload and every 180 s.
struct CorePlaybackTracker: PlaybackTracker {
    let runtime: CoreRuntime

    #if os(tvOS)
    private static let device = "tvos"
    #else
    private static let device = "macos"
    #endif

    func begin(_ candidate: StreamCandidate) {
        send(.load(.player(selection: candidate.tracking.payload)))
    }

    func progress(_ position: Duration, of duration: Duration) {
        send(.player(.timeChanged(timeMs: position.milliseconds, durationMs: duration.milliseconds, device: Self.device)))
    }

    func seek(to position: Duration, of duration: Duration) {
        send(.player(.seek(timeMs: position.milliseconds, durationMs: duration.milliseconds, device: Self.device)))
    }

    func paused(_ paused: Bool) {
        send(.player(.pausedChanged(paused: paused)))
    }

    func ended() {
        send(.player(.ended))
    }

    func movedToNext() {
        send(.player(.nextVideo))
    }

    func stop() {
        send(.unload)
    }

    /// Core finds the next video once the selection's meta item loads, then asks the selected
    /// stream's add-on for its streams and picks the one in the same binge group.
    func upNext(after candidate: StreamCandidate) -> AsyncStream<UpNext?> {
        let (results, continuation) = AsyncStream.makeStream(of: UpNext?.self, bufferingPolicy: .bufferingNewest(1))
        let answers = runtime.observe(.player, as: PlayerState.self) { Self.answer(for: candidate, in: $0) }
        let task = Task {
            var isSelected = false
            for await answer in answers {
                guard case .selected(let next) = answer else {
                    // Before the load lands another selection still shows; after, another candidate replaced this one.
                    if isSelected { break } else { continue }
                }
                isSelected = true
                continuation.yield(next)
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
        let selections = runtime.observe(.player, as: PlayerState.self) { player -> RememberedSelection in
            player.plays(candidate, from: source) ? .current(player.streamState?.choices) : .other
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
}

private extension CorePlaybackTracker {
    /// What one state of core's player model says about the episode after a candidate.
    enum Answer: Equatable, Sendable {
        case otherSelection
        case selected(UpNext?)
    }

    static func answer(for candidate: StreamCandidate, in player: PlayerState) -> Answer {
        guard let selected = player.selected, let source = candidate.source,
              selected.stream.source == .url(source.url), selected.streamRequest?.path.id == candidate.item.rawValue
        else { return .otherSelection }
        guard let video = player.nextVideo, let id = PlayableID(video.id) else { return .selected(nil) }
        let show = player.metaItem?.content?.readyContent
        return .selected(UpNext(
            video: id,
            show: show?.name ?? "",
            title: video.title,
            thumbnail: video.thumbnail.flatMap(URL.init(string:)),
            backdrop: show?.background.flatMap(URL.init(string:)),
            stream: nextCandidate(for: id, in: player)
        ))
    }

    /// Core's next stream as a candidate that plays here, tracked against the same meta item.
    static func nextCandidate(for video: PlayableID, in player: PlayerState) -> StreamCandidate? {
        guard let stream = player.nextStream, let streams = player.nextStreams,
              let addon = ManifestURL(streams.request.base),
              let index = streams.content?.readyContent?.firstIndex(where: { $0.raw == stream.raw })
        else { return nil }
        let candidate = CoreStreamResults.candidate(
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

private extension StreamItemState {
    /// The managed keys, in core's terms: an embedded track by the engine's number, an add-on's file
    /// by its URL. Ids the app did not write read as nothing chosen.
    var choices: TrackChoices {
        get {
            let subtitles: TrackChoices.Subtitles? = subtitleTrack.flatMap { track in
                if track.embedded {
                    Int(track.id).map { .builtIn(TrackChoices.Track(number: $0, language: track.language)) }
                } else {
                    URL(string: track.id).map { .addon($0, language: track.language) }
                }
            }
            return TrackChoices(
                audio: audioTrack.flatMap { track in Int(track.id).map { TrackChoices.Track(number: $0, language: track.language) } },
                subtitles: subtitles,
                speed: playbackSpeed.flatMap(PlaybackSpeed.init(rawValue:))
            )
        }
        set {
            audioTrack = newValue.audio.map { AudioTrack(id: String($0.number), language: $0.language) }
            subtitleTrack = switch newValue.subtitles {
            case nil: nil
            case .builtIn(let track): SubtitleTrack(id: String(track.number), embedded: true, language: track.language)
            case .addon(let url, let language): SubtitleTrack(id: url.absoluteString, embedded: false, language: language)
            }
            playbackSpeed = newValue.speed?.rawValue
        }
    }
}

private extension Duration {
    var milliseconds: UInt64 {
        UInt64(max(0, self / .milliseconds(1)))
    }
}
