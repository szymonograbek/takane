import Foundation

/// Turns what the player does with a source's stream into the reports a Jellyfin server keeps its
/// resume position and watched state by: started once the position is known, progress every
/// `interval` and on pause, stopped at the last position.
struct JellyfinPlaybackReports: Sendable {
    /// How often progress is reported while playing, as Jellyfin's own clients do.
    static let interval = Duration.seconds(10)

    private struct Playing {
        let source: SourceID
        let item: SourceItemID
        let file: SourceItemID
        let playSession: String
        var position: Duration
        var isPaused: Bool
        var reportedAt: ContinuousClock.Instant
    }

    private enum State {
        case idle
        /// Began, with no position yet.
        case opened(SourceID, SourceItemID, file: SourceItemID)
        case playing(Playing)
    }

    private var state = State.idle

    mutating func reports(after event: InProcessPlayback, at now: ContinuousClock.Instant) -> [JellyfinPlaybackReport] {
        switch (state, event) {
        case (_, .began(let url)):
            let stopped = stop()
            if let source = SourceID(url.addonID), case .video(let item, let file)? = SourcePlaceholder(url) {
                state = .opened(source, item, file: file)
            }
            return stopped
        case (.opened(let source, let item, let file), .position(let position)):
            let playing = Playing(
                source: source, item: item, file: file, playSession: UUID().uuidString, position: position, isPaused: false, reportedAt: now
            )
            state = .playing(playing)
            return [report(.started, playing)]
        case (.playing(var playing), .position(let position)):
            playing.position = position
            guard now - playing.reportedAt >= Self.interval else {
                state = .playing(playing)
                return []
            }
            playing.reportedAt = now
            state = .playing(playing)
            return [report(.progress, playing)]
        case (.playing(var playing), .paused(let paused)):
            guard paused != playing.isPaused else { return [] }
            playing.isPaused = paused
            playing.reportedAt = now
            state = .playing(playing)
            return [report(.progress, playing)]
        case (_, .stopped):
            return stop()
        case (.idle, .position), (.idle, .paused), (.opened, .paused):
            return []
        }
    }

    private mutating func stop() -> [JellyfinPlaybackReport] {
        defer { state = .idle }
        guard case .playing(let playing) = state else { return [] }
        return [report(.stopped, playing)]
    }

    private func report(_ kind: JellyfinPlaybackReport.Kind, _ playing: Playing) -> JellyfinPlaybackReport {
        JellyfinPlaybackReport(
            kind: kind, source: playing.source, item: playing.item, file: playing.file, playSession: playing.playSession,
            position: playing.position, isPaused: playing.isPaused
        )
    }
}
