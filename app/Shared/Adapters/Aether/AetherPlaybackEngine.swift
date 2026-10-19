import AetherEngine
import Combine
import CoreGraphics
import Foundation
import SwiftUI

/// `PlaybackEngine` over AetherEngine, which remuxes a stream into AVPlayer where it can and
/// decodes it in software where it cannot.
///
/// Everything runs on the main actor, as AetherEngine does. Its published state becomes
/// `PlaybackEvent`s, each sent once per change. Time comes from its `clock`, which ticks without
/// waking the engine's other observers.
final class AetherPlaybackEngine: PlaybackEngine {
    let events: AsyncStream<PlaybackEvent>

    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    private let player: AetherEngine
    /// The load in flight. A newer load or a stop cancels it.
    private var loading: Task<Void, Never>?
    private var reported = Reported()
    /// Subtitle files added to the current load, by the engine's id for the track.
    private var externalFiles: [Int: URL] = [:]
    private var observations: Set<AnyCancellable> = []

    init() throws(PlaybackError) {
        // Lines arrive from the engine's own threads; `Log` queues its writes.
        EngineLog.handler = { @Sendable line in Log.player.debug(line) }
        (events, continuation) = AsyncStream.makeStream(of: PlaybackEvent.self)
        do {
            player = try AetherEngine()
        } catch {
            throw .failed(reason: "\(error)")
        }
        observe()
        Log.player.info("AetherEngine \(AetherEngine.version) ready")
    }

    /// The view video renders into. The engine moves each session's layer into it.
    func surface() -> some View {
        AetherPlayerSurface(engine: player)
    }

    func load(_ source: PlaybackSource, from start: Duration, languages: TrackLanguages) {
        loading?.cancel()
        reported = Reported()
        externalFiles = [:]
        let url = source.url
        let startPosition = start > .zero ? start / .seconds(1) : nil
        let options = LoadOptions(
            httpHeaders: source.headers,
            preferredAudioLanguages: languages.audio.map { [$0.code] } ?? [],
            preferredSubtitleLanguages: languages.subtitles.inPreferenceOrder.map(\.code)
        )
        Log.player.info("load \(url.absoluteString) from \(startPosition ?? 0)s headers=\(source.headers.keys.sorted())")
        loading = Task { [player] in
            do {
                try await player.load(url: url, startPosition: startPosition, options: options)
            } catch is CancellationError {
                // A newer load or a stop took over.
            } catch {
                // The engine publishes the failure as `.error` too, and that is where it is reported.
                Log.player.error("load failed: \(error)")
            }
        }
    }

    func setPaused(_ paused: Bool) {
        if paused { player.pause() } else { player.play() }
    }

    func seek(by offset: Duration) {
        // A seek still landing is where the next one starts from.
        let from = player.seekTarget ?? player.clock.currentTime
        seek(to: .seconds(from) + offset)
    }

    func seek(to position: Duration) {
        let seconds = max(0, position / .seconds(1))
        Task { [player] in await player.seek(to: seconds) }
    }

    func select(_ track: MediaTrack.ID) {
        switch track.kind {
        case .audio: player.selectAudioTrack(index: track.number)
        case .subtitle: player.selectSubtitleTrack(index: track.number)
        }
    }

    func turnOffSubtitles() {
        player.clearSubtitle()
    }

    func addSubtitles(_ file: URL, title: String, language: String) {
        Log.player.info("add subtitles \(file.absoluteString) \(language)")
        let track = player.addExternalSubtitleTrack(ExternalSubtitleTrack(url: file, name: title, language: language))
        externalFiles[track.id] = file
        player.selectSubtitleTrack(index: track.id)
    }

    func setSpeed(_ speed: PlaybackSpeed) {
        player.setRate(Float(speed.rawValue))
        // The engine publishes no rate. The one set holds until the next source.
        continuation.yield(.speed(speed))
    }

    func stop() {
        loading?.cancel()
        loading = nil
        player.stop()
    }

    func diagnostics() -> [String: String] {
        let telemetry = player.diagnostics.liveTelemetry
        let values: [String: String?] = [
            "route": player.videoRoute.rawValue,
            "container": player.sourceContainerFormat,
            "videoCodec": player.sourceVideoCodecName,
            "videoDecoder": player.activeVideoDecoder,
            "videoFormat": "\(player.videoFormat)",
            "sourceVideoFormat": "\(player.sourceVideoFormat)",
            "audioDecoder": player.activeAudioDecoder,
            "audioDelivery": player.audioDelivery.rawValue,
            "observedFps": telemetry?.observedFps.map { String(format: "%.3f", $0) },
            "droppedFrames": telemetry?.droppedFrameCount.map(String.init),
            "averageBitrateMbps": telemetry?.averageBitrateMbps.map { String(format: "%.1f", $0) },
        ]
        return values.compactMapValues(\.self)
    }

    /// The frame at the playhead, decoded from what the session already cached, so a debrid link
    /// that allows one connection is not asked for a second. Nil when that part is not cached, or,
    /// on the software route, when the frame lies too far past a keyframe to decode as a still.
    func snapshot() async -> CGImage? {
        await player.scrubThumbnail(atSeconds: player.clock.currentTime, maxWidth: 1920)
    }

    private func observe() {
        player.$playbackPhase.removeDuplicates()
            .sink { [weak self] phase in self?.phaseChanged(phase) }
            .store(in: &observations)
        player.clock.$currentTime.removeDuplicates()
            .sink { [weak self] seconds in self?.continuation.yield(.position(.seconds(seconds))) }
            .store(in: &observations)
        player.$duration
            .sink { [weak self] seconds in self?.send(.duration(.seconds(seconds)), on: \.duration) }
            .store(in: &observations)
        player.$sourceVideoWidth.combineLatest(player.$sourceVideoHeight)
            // The pixel aspect ratio is set right after the size.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] width, height in self?.videoSizeChanged(width: width, height: height) }
            .store(in: &observations)
        player.$activeVideoDecoder
            .sink { [weak self] decoder in
                guard let decoder else { return }
                self?.send(.decoder(decoder), on: \.decoder)
            }
            .store(in: &observations)
        Publishers.CombineLatest4(player.$audioTracks, player.$activeAudioTrackIndex, player.$subtitleTracks, player.$activeSubtitleTrackIndex)
            .sink { [weak self] audio, audioIndex, subtitles, subtitleIndex in
                guard let self else { return }
                let tracks = audio.map { MediaTrack($0, kind: .audio, selected: audioIndex, file: nil) }
                    + subtitles.map { MediaTrack($0, kind: .subtitle, selected: subtitleIndex, file: externalFiles[$0.id]) }
                send(.tracks(tracks), on: \.tracks)
            }
            .store(in: &observations)
        // Cues arrive ahead of time, stamped with source PTS; `sourceTime` is the PTS on screen.
        player.$subtitleCues.combineLatest(player.clock.$sourceTime)
            .map { cues, time in cues.filter { $0.startTime <= time && time < $0.endTime } }
            .sink { [weak self] visible in
                guard let self else { return }
                let video = reported.video
                let cues = visible.compactMap { cue -> SubtitleCue? in
                    if case .image(let image) = cue.body { return SubtitleCue(image, on: video) }
                    return cue.text.map(SubtitleCue.text)
                }
                send(.subtitles(cues), on: \.subtitles)
            }
            .store(in: &observations)
    }

    private func phaseChanged(_ phase: PlaybackPhase) {
        switch phase {
        case .idle:
            continuation.yield(.stopped)
        case .loading, .seeking, .rebuffering, .stalled:
            send(.buffering(true), on: \.buffering)
        case .playing, .paused:
            send(.loaded, on: \.loaded)
            send(.buffering(false), on: \.buffering)
            send(.paused(phase == .paused), on: \.paused)
        case .ended:
            continuation.yield(.ended)
        case .error(let message):
            Log.player.error("playback failed (\(player.errorInfo?.kind.rawValue ?? "unclassified")): \(message)")
            continuation.yield(.failed(reason: message))
        }
    }

    private func videoSizeChanged(width: Int32, height: Int32) {
        guard width > 0, height > 0 else { return }
        let size = VideoSize(width: Int((Double(width) * player.sourceVideoPixelAspectRatio).rounded()), height: Int(height))
        send(.videoSize(size), on: \.videoSize)
    }

    /// Sends `event` unless it is what this load last sent on `channel`.
    private func send(_ event: PlaybackEvent, on channel: WritableKeyPath<Reported, PlaybackEvent?>) {
        guard reported[keyPath: channel] != event else { return }
        reported[keyPath: channel] = event
        continuation.yield(event)
    }
}

/// The last event the current load sent on each channel, so each goes out once per change. A new
/// load starts empty, so its first values go out even when they equal the previous source's.
private struct Reported {
    var loaded: PlaybackEvent?
    var paused: PlaybackEvent?
    var buffering: PlaybackEvent?
    var duration: PlaybackEvent?
    var videoSize: PlaybackEvent?
    var decoder: PlaybackEvent?
    var tracks: PlaybackEvent?
    var subtitles: PlaybackEvent?

    var video: VideoSize? {
        if case .videoSize(let size)? = videoSize { size } else { nil }
    }
}
