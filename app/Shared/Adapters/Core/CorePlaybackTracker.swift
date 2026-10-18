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

    func paused(_ paused: Bool) {
        send(.player(.pausedChanged(paused: paused)))
    }

    func ended() {
        send(.player(.ended))
    }

    func stop() {
        send(.unload)
    }

    private func send(_ action: CoreAction) {
        do {
            try runtime.dispatch(action, to: .player)
        } catch {
            Log.core.error("player dispatch failed: \(error)")
        }
    }
}

private extension Duration {
    var milliseconds: UInt64 {
        UInt64(max(0, self / .milliseconds(1)))
    }
}
