import CoreGraphics
import Foundation
import Observation

/// Observable playback state over one `MPVEngine`.
@MainActor
@Observable
final class PlayerController {
    enum Phase: Equatable {
        case idle
        case loading(URL)
        case playing
        case paused
        case ended
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var isBuffering = false
    /// Seconds.
    private(set) var position: Double = 0
    /// Seconds; zero until known.
    private(set) var duration: Double = 0
    private(set) var videoSize: (width: Int, height: Int)?
    private(set) var hardwareDecoder: String?

    /// Called for each playback change, after state is updated. Used to report progress to core.
    @ObservationIgnored var onChange: ((MPVEvent) -> Void)?

    /// Nil when mpv failed to start; the app keeps running and `phase` explains why.
    @ObservationIgnored private var engine: MPVEngine?

    init() {
        do {
            engine = try MPVEngine { [weak self] event in self?.handle(event) }
        } catch {
            Log.player.error("mpv failed to start: \(error)")
            phase = .failed("mpv failed to start: \(error)")
        }
    }

    /// The layer the video renders into, for `MPVVideoView`.
    var videoLayer: MPVMetalLayer? { engine?.layer }

    func play(_ url: URL, headers: [String: String] = [:]) {
        guard let engine else { return }
        position = 0
        duration = 0
        videoSize = nil
        phase = .loading(url)
        engine.load(url, headers: headers)
        engine.setPaused(false)
    }

    func togglePause() {
        switch phase {
        case .playing: engine?.setPaused(true)
        case .paused: engine?.setPaused(false)
        default: Log.player.debug("togglePause ignored in \(phase)")
        }
    }

    func seek(by seconds: Double) {
        engine?.seek(by: seconds)
    }

    func stop() {
        engine?.stop()
        phase = .idle
    }

    /// Output health: render target size (the view in pixels), dropped frames, audio output and format.
    func playbackDiagnostics() -> [String: String] {
        let names = [
            "osd-width", "osd-height", "frame-drop-count", "decoder-frame-drop-count", "vo-delayed-frame-count",
            "estimated-vf-fps", "video-codec", "current-ao", "audio-codec-name", "audio-out-params/channel-count",
            "audio-out-params/samplerate", "mute", "volume",
        ]
        return names.reduce(into: [:]) { diagnostics, name in
            diagnostics[name] = engine?.property(name)
        }
    }

    /// Runs off the main actor: mpv may need the main thread to render the frame it returns.
    func snapshot() async -> CGImage? {
        guard let engine else { return nil }
        return await Task.detached { engine.snapshot() }.value
    }

    private func handle(_ event: MPVEvent) {
        switch event {
        case .fileLoaded:
            phase = .playing
        case .endFile(let reason, let error):
            if let error {
                phase = .failed("\(reason): \(error)")
            } else if reason == "eof" {
                phase = .ended
            } else if case .loading = phase {
                // A new loadfile replaced the previous file; the new one is still loading.
            } else {
                phase = .idle
            }
        case .timePosition(let seconds):
            position = seconds
        case .duration(let seconds):
            duration = seconds
        case .paused(let paused):
            switch phase {
            case .playing where paused: phase = .paused
            case .paused where !paused: phase = .playing
            default: break
            }
        case .buffering(let buffering):
            isBuffering = buffering
        case .videoSize(let width, let height):
            videoSize = width > 0 && height > 0 ? (width, height) : nil
        case .hardwareDecoder(let name):
            hardwareDecoder = name
        }
        onChange?(event)
    }
}
