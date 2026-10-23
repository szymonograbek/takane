import Foundation

/// Moving along the timeline with left and right: a tap jumps, a hold scans.
extension PlayerFeature {
    enum Direction: Sendable {
        case backward, forward

        var sign: Int {
            switch self {
            case .backward: -1
            case .forward: 1
            }
        }
    }

    enum TimelineEvent: Sendable {
        /// A tap of left or right, at `at`.
        case step(Direction, at: ContinuousClock.Instant)
        /// Left or right held down.
        case hold(Direction)
        /// Time for a scan to move on.
        case tick
    }

    /// Fast forward or rewind: the engine stays paused while the scan's playhead moves `rate`
    /// times real time, seeking the engine after it.
    struct Scan: Equatable, Sendable {
        let direction: Direction
        var rate: ScanRate
        /// Where the scan has reached. The UI shows this instead of the engine's lagging position.
        var position: Duration
    }

    enum ScanRate: Int, Sendable {
        case times2 = 2, times4 = 4, times8 = 8, times16 = 16, times32 = 32

        /// The next rate up, or this one at the cap.
        var faster: Self { Self(rawValue: rawValue * 2) ?? self }
        /// The next rate down, or nil below 2×, which means normal playback.
        var slower: Self? { Self(rawValue: rawValue / 2) }
    }

    /// Taps in one direction close together, and how far they have jumped in all, which the
    /// player shows beside the picture.
    struct StepStreak: Equatable, Sendable {
        let direction: Direction
        let distance: Duration
        let lastTap: ContinuousClock.Instant
    }

    static let scanTickInterval = Duration.milliseconds(250)
    /// How soon a tap must follow the last to join its streak.
    static let streakWindow = Duration.seconds(1)
}

extension PlayerFeature.Session {
    typealias Effect = PlayerFeature.Effect

    /// The scan's playhead while scanning, else the engine's position.
    var displayedPosition: Duration {
        scan?.position ?? position
    }

    /// Without a scan a tap jumps and a hold starts one. During a scan, a tap or hold in its
    /// direction speeds it up, and one against it slows it down until playback resumes.
    mutating func apply(_ event: PlayerFeature.TimelineEvent) -> [Effect] {
        switch (event, scan) {
        case (.step(let direction, let instant), nil):
            return step(direction, at: instant)
        case (.hold(let direction), nil):
            return startScan(direction)
        case (.step(let direction, _), let scan?), (.hold(let direction), let scan?):
            guard let rate = direction == scan.direction ? scan.rate.faster : scan.rate.slower else { return endScan() }
            self.scan?.rate = rate
            return []
        case (.tick, let scan?):
            return tick(scan)
        case (.tick, nil):
            return []
        }
    }

    /// Pauses or resumes, or ends a scan, which resumes.
    mutating func togglePause() -> [Effect] {
        guard scan == nil else { return endScan() }
        switch phase {
        case .playing: return [.setPaused(true)]
        case .paused: return [.setPaused(false)]
        case .opening, .ended: return []
        }
    }

    /// Ends a scan, if there is one, and resumes playback.
    mutating func endScan() -> [Effect] {
        guard scan != nil else { return [] }
        scan = nil
        return [.setPaused(false)]
    }

    /// Each tap jumps one `seekStep`, as the system player does. A tap in the same direction within
    /// `streakWindow` of the last adds its step to the streak.
    private mutating func step(_ direction: PlayerFeature.Direction, at instant: ContinuousClock.Instant) -> [Effect] {
        guard phase == .playing || phase == .paused else { return [] }
        var distance = seekStep.duration
        if let streak, streak.direction == direction, instant - streak.lastTap <= PlayerFeature.streakWindow {
            distance += streak.distance
        }
        streak = PlayerFeature.StepStreak(direction: direction, distance: distance, lastTap: instant)
        return [.seek(by: seekStep.duration * direction.sign)]
    }

    /// Scanning needs the duration, which bounds it.
    private mutating func startScan(_ direction: PlayerFeature.Direction) -> [Effect] {
        guard phase == .playing || phase == .paused, duration > .zero else { return [] }
        scan = PlayerFeature.Scan(direction: direction, rate: .times2, position: position)
        streak = nil
        return [.setPaused(true), .scanTick]
    }

    /// Reaching either end of the stream ends the scan there.
    private mutating func tick(_ scan: PlayerFeature.Scan) -> [Effect] {
        let target = scan.position + PlayerFeature.scanTickInterval * (scan.rate.rawValue * scan.direction.sign)
        guard target > .zero, target < duration else {
            return [.seekTo(min(max(target, .zero), duration))] + endScan()
        }
        self.scan?.position = target
        return [.seekTo(target), .scanTick]
    }
}
