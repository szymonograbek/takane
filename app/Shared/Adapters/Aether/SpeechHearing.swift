import AetherEngine
import Foundation

/// Hears the playing session's audio for speech while asked to: installs the engine's audio tap
/// once the session plays, feeds it to a `SpeechListener`, and removes it when asked to stop.
@MainActor
final class SpeechHearing {
    private let player: AetherEngine
    /// Whether hearing was asked for, until the next `reset`.
    private var isAsked = false
    private var listener = SpeechListener()
    /// Feeds the installed tap's audio to `listener`.
    private var listening: Task<Void, Never>?

    init(player: AetherEngine) {
        self.player = player
    }

    /// Where people spoke in what was heard since the last `reset`.
    var history: SpeechStore {
        listener.history
    }

    /// Starts or stops hearing. Stopping keeps what was heard.
    func hear(_ asked: Bool) {
        Log.player.info("hearing speech \(asked ? "on" : "off")")
        isAsked = asked
        if asked {
            sessionChanged(phase: player.playbackPhase, backend: player.playbackBackend)
        } else {
            removeTap()
        }
    }

    /// Starts hearing once the session plays, if asked to. A reload of the session, such as for
    /// another audio track, ends what the tap sends, and the next play installs it again.
    func sessionChanged(phase: PlaybackPhase, backend: PlaybackBackend) {
        guard isAsked, listening == nil, phase == .playing, backend != .none else { return }
        let taps = player.installAudioTap()
        guard player.audioTapHasDeliverySource else {
            Log.player.info("no audio to hear speech in")
            return
        }
        let listener = listener
        listening = Task { [weak self] in
            // A new tap does not follow on from audio heard before it.
            var continuing = false
            for await tap in taps {
                guard let channel = tap.buffer.floatChannelData?[0] else { continue }
                let samples = Array(UnsafeBufferPointer(start: channel, count: Int(tap.buffer.frameLength)))
                await listener.hear(samples, from: tap.sourceTime, continuing: continuing && !tap.discontinuity)
                continuing = true
            }
            // Removing the tap cancelled it and cleared `listening` itself.
            guard !Task.isCancelled else { return }
            self?.listening = nil
        }
    }

    /// Stops hearing and forgets what was heard, for a new load or a stop.
    func reset() {
        isAsked = false
        removeTap()
        listener = SpeechListener()
    }

    private func removeTap() {
        listening?.cancel()
        listening = nil
        player.removeAudioTap()
    }
}
