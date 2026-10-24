import Foundation

/// What the engine reports, kept in the session.
extension PlayerFeature.Session {
    /// Updates the session for an engine event. A `.stopped` while opening is the previous file
    /// making way for this one, so it changes nothing.
    mutating func apply(_ event: PlaybackEvent) -> [Effect] {
        switch event {
        case .loaded:
            phase = .playing
        case .ended:
            phase = .ended
            scan = nil
            return [.report(.ended)]
        case .stopped, .failed:
            break
        case .position(let reported):
            // Engines can report a slightly negative position for streams starting before PTS 0.
            let position = max(.zero, reported)
            self.position = position
            let second = position.components.seconds
            guard second != reportedSecond, duration > .zero else { return [] }
            reportedSecond = second
            return [.report(.progress(position, of: duration))]
        case .seeking(let target):
            guard duration > .zero else { return [] }
            // The position that follows lands on the target, which this report already covers.
            reportedSecond = target.components.seconds
            return [.report(.seek(to: target, of: duration))]
        case .duration(let duration):
            self.duration = duration
            guard segments == nil, duration > .zero else { return [] }
            segments = .loading
            return [.findSegments(candidate.item, duration: duration, from: skipSegmentSource)]
        case .paused(let paused):
            switch phase {
            case .playing where paused: phase = .paused
            case .paused where !paused: phase = .playing
            case .opening, .playing, .paused, .ended: break
            }
            return [.report(.paused(paused))]
        case .buffering(let buffering):
            isBuffering = buffering
        case .videoSize(let size):
            videoSize = size
        case .decoder(let name):
            decoder = name
        case .tracks(let tracks):
            self.tracks = tracks
            return continueRestore() + preferredSubtitles()
        case .speed(let speed):
            self.speed = speed
        case .subtitles(let cues):
            subtitles = cues
        case .cueTimeline(let cues):
            cueTimeline = cues
        case .chapters(let chapters):
            self.chapters = chapters
        }
        return []
    }
}
