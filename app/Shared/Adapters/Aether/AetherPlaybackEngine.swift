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
    private var externalFiles: [Int: Redacted<URL>] = [:]
    /// The seek in flight, from its `.began` until it ends. Meanwhile the clock can still read the
    /// pre-seek position: before the engine's host takes the clock over, and after AVPlayer misses its
    /// landing deadline. Core would count that as watched, so only the target gets through.
    private var seeking: SeekEvent?
    /// The subtitle delay in seconds, which moves the cues shown against the clock.
    private let subtitleDelay = CurrentValueSubject<Double, Never>(0)
    /// How far the clock the cues are stamped on runs ahead of the position reported.
    private var sourceClock = SourceClock()
    private var observations: Set<AnyCancellable> = []
    /// Hears where people spoke in the audio since the current load.
    private var speech = SpeechListener()
    /// Hears the playing session's audio into `speech`.
    private var listening: Task<Void, Never>?

    /// `muted` plays every stream silently, for automated runs.
    init(muted: Bool) throws(PlaybackError) {
        // Lines arrive from the engine's own threads; `Log` queues its writes.
        EngineLog.handler = { @Sendable line in Log.player.debug(RedactedMask.engineLine(line)) }
        (events, continuation) = AsyncStream.makeStream(of: PlaybackEvent.self)
        do {
            player = try AetherEngine()
        } catch {
            throw .failed(reason: "\(error)")
        }
        if muted {
            // The engine remembers it and applies it to every session it builds later.
            player.volume = 0
            Log.player.info("muted")
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
        subtitleDelay.send(0)
        sourceClock = SourceClock()
        stopListening()
        let url = source.url.rawValue
        let startPosition = start > .zero ? start / .seconds(1) : nil
        let options = LoadOptions(
            httpHeaders: source.headers,
            preferredAudioLanguages: languages.audio?.inPreferenceOrder.map(\.code) ?? [],
            preferredSubtitleLanguages: languages.subtitles?.inPreferenceOrder.map(\.code) ?? []
        )
        Log.player.info("load \(source.url) from \(startPosition ?? 0)s headers=\(source.headers.keys.sorted())")
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

    func addSubtitles(_ file: Redacted<URL>, from source: PlaybackSource, title: String, language: String) {
        Log.player.info("add subtitles \(file) \(language) headers=\(source.headers.keys.sorted())")
        // Headers of their own, never the stream's: those can be another server's credentials.
        let track = player.addExternalSubtitleTrack(
            ExternalSubtitleTrack(url: source.url.rawValue, name: title, language: language, httpHeaders: source.headers)
        )
        externalFiles[track.id] = file
        player.selectSubtitleTrack(index: track.id)
    }

    func setSpeed(_ speed: PlaybackSpeed) {
        player.setRate(Float(speed.rawValue))
        // The engine publishes no rate. The one set holds until the next source.
        continuation.yield(.speed(speed))
    }

    func setSubtitleDelay(_ delay: SubtitleDelay) {
        subtitleDelay.send(delay.duration / .seconds(1))
    }

    func speechActivity(in range: Range<Duration>) -> SpeechActivity {
        speech.history.activity(in: range, on: sourceClock)
    }

    func stop() {
        loading?.cancel()
        loading = nil
        stopListening()
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
        // Published before they change: read once both have.
        player.$playbackPhase.combineLatest(player.$playbackBackend).receive(on: DispatchQueue.main)
            .sink { [weak self] phase, backend in self?.listenForSpeech(phase: phase, backend: backend) }
            .store(in: &observations)
        player.clock.$currentTime.removeDuplicates()
            .sink { [weak self] seconds in self?.positionChanged(seconds) }
            .store(in: &observations)
        player.seekEvents
            .sink { [weak self] seek in self?.seekChanged(seek) }
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
        // Published before they change: read once the engine has set both clocks for the tick.
        player.clock.$currentTime.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.clockTicked() }
            .store(in: &observations)
        player.$subtitleCues.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sendCueTimeline() }
            .store(in: &observations)
        // Cues arrive ahead of time, stamped with source PTS; `sourceTime` is the PTS on screen.
        Publishers.CombineLatest3(player.$subtitleCues, player.clock.$sourceTime, subtitleDelay)
            .map { cues, time, delay in
                let shown = time - delay
                return cues.filter { $0.startTime <= shown && shown < $0.endTime }
            }
            .sink { [weak self] visible in
                guard let self else { return }
                let video = reported.video
                let cues = visible.map { cue -> SubtitleCue in
                    switch cue.body {
                    case .image(let image): SubtitleCue(image, on: video)
                    case .text(let plain): .text(SubtitleText(runs: [SubtitleTextRun(text: plain, color: nil)], placement: cue.placement))
                    case .richText(let runs): .text(SubtitleText(runs: runs, placement: cue.placement))
                    }
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

    /// Learns how far the source clock runs ahead of the position, away from seeks, which can leave
    /// the source clock on the old frame.
    private func clockTicked() {
        guard seeking == nil, sourceClock.read(position: player.clock.currentTime, source: player.clock.sourceTime) else { return }
        Log.player.info("source clock ahead of the position by \(sourceClock.offset)s")
        sendCueTimeline()
    }

    /// The selected track's cues, timed like the position. Sent only when they differ from the last.
    private func sendCueTimeline() {
        let cues = player.subtitleCues
        let starts = cues.map(\.startTime).sorted()
        let timeline = cues.map { cue in
            TimedCue(number: cue.id, start: cue.startTime, end: cue.endTime, text: cue.text, starts: starts, clock: sourceClock)
        }
        send(.cueTimeline(timeline), on: \.cueTimeline)
    }

    private func positionChanged(_ seconds: Double) {
        if let seeking, seconds != seeking.target { return }
        continuation.yield(.position(.seconds(seconds)))
    }

    /// A seek begins before the clock moves to its target, so the jump never reads as watched time.
    private func seekChanged(_ seek: SeekEvent) {
        switch seek.outcome {
        case .began:
            seeking = seek
            continuation.yield(.seeking(to: .seconds(seek.target)))
        case .landed, .stalled:
            guard seek.id == seeking?.id else { return }
            seeking = nil
            // Where it landed, or the target a stalled seek holds the clock at.
            continuation.yield(.position(.seconds(player.clock.currentTime)))
        case .superseded, .rejected:
            // A newer seek's `.began` follows, or the seek ended without moving the clock.
            if seek.id == seeking?.id { seeking = nil }
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

/// Hearing speech in the playing session's audio.
private extension AetherPlaybackEngine {
    /// Starts hearing the playing session's audio into `speech`, once it plays. A reload of the
    /// session, such as for another audio track, ends what the engine sends, and the next play
    /// starts it again.
    func listenForSpeech(phase: PlaybackPhase, backend: PlaybackBackend) {
        guard listening == nil, phase == .playing, backend != .none else { return }
        let taps = player.installAudioTap()
        guard player.audioTapHasDeliverySource else {
            Log.player.info("no audio to hear speech in")
            return
        }
        let speech = speech
        listening = Task { [weak self] in
            for await tap in taps {
                guard let channel = tap.buffer.floatChannelData?[0] else { continue }
                let samples = Array(UnsafeBufferPointer(start: channel, count: Int(tap.buffer.frameLength)))
                await speech.hear(samples, from: tap.sourceTime, continuing: !tap.discontinuity)
            }
            // A load or a stop cancelled it and cleared `listening` itself.
            guard !Task.isCancelled else { return }
            self?.listening = nil
        }
    }

    /// Forgets the speech heard. The engine ends its tap with the session.
    func stopListening() {
        listening?.cancel()
        listening = nil
        speech = SpeechListener()
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
    var cueTimeline: PlaybackEvent?

    var video: VideoSize? {
        if case .videoSize(let size)? = videoSize { size } else { nil }
    }
}
