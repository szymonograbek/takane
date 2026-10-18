import Foundation
import Observation

/// Plays a core stream in mpv and keeps core's player model informed, so core can track
/// progress, watched state and continue-watching.
@MainActor
@Observable
final class PlaybackSession {
    let player: PlayerController
    private(set) var stream: Stream?

    @ObservationIgnored private let core: CoreStore
    @ObservationIgnored private var lastReportedSecond = -1

    #if os(tvOS)
    private static let device = "tvos"
    #else
    private static let device = "macos"
    #endif

    init(core: CoreStore, player: PlayerController) {
        self.core = core
        self.player = player
        player.onChange = { [weak self] event in self?.report(event) }
    }

    /// - Parameters:
    ///   - streamRequest: the addon request that returned `stream`.
    ///   - metaRequest: the request for the item's metadata, so core can attach progress to it.
    func play(_ stream: Stream, streamRequest: ResourceRequest, metaRequest: ResourceRequest?) {
        guard let url = stream.playableURL else {
            Log.player.error("not playable: \(stream.source)")
            return
        }
        Log.player.info("play \(stream.name ?? "?") | \(stream.filename ?? stream.description ?? "") | \(url.absoluteString)")
        self.stream = stream
        lastReportedSecond = -1
        let selection = PlayerSelection(
            stream: stream.raw,
            streamRequest: streamRequest,
            metaRequest: metaRequest,
            subtitlesPath: nil
        )
        core.send(.load(.player(selection)), to: .player)
        player.play(url, headers: stream.requestHeaders)
    }

    func stop() {
        Log.player.info("stop")
        player.stop()
        stream = nil
        core.send(.unload, to: .player)
    }

    private func report(_ event: MPVEvent) {
        guard stream != nil else { return }
        switch event {
        case .timePosition(let rawSeconds):
            // mpv can report a slightly negative position for streams starting before PTS 0.
            let seconds = max(0, rawSeconds)
            let second = Int(seconds)
            guard second != lastReportedSecond, player.duration > 0 else { return }
            lastReportedSecond = second
            core.send(
                .player(.timeChanged(
                    timeMs: UInt64(seconds * 1000),
                    durationMs: UInt64(player.duration * 1000),
                    device: Self.device
                )),
                to: .player
            )
        case .paused(let paused):
            core.send(.player(.pausedChanged(paused: paused)), to: .player)
        case .endFile(let reason, _) where reason == "eof":
            core.send(.player(.ended), to: .player)
        default:
            break
        }
    }
}
