/// Offering the episode after this one as the end nears, and moving on to it.
extension PlayerFeature {
    /// The episode after this one, and whether the viewer turned it down.
    enum UpNextOffer: Equatable, Sendable {
        /// Nothing follows, or the tracker has not found what does yet.
        case notFound
        case offered(UpNext)
        /// It neither shows again nor plays by itself for this session.
        case dismissed
    }

    enum UpNextEvent: Sendable {
        /// Moves on to the offered episode: plays its stream, or leaves the choice of one to the viewer.
        case play
        case dismiss
    }

    static func reduce(_ event: UpNextEvent, in session: Session, replacing state: inout State) -> [Effect] {
        var session = session
        switch event {
        case .play:
            guard case .offered(let next) = session.upNext else { return [] }
            if let stream = next.stream { return play(stream, of: next, replacing: &state) }
            // The viewer picks a stream for it, so the offer makes way.
            session.upNext = .dismissed
            state = .active(session)
            return [.report(.movedToNext)]
        case .dismiss:
            guard case .offered = session.upNext else { return [] }
            session.upNext = .dismissed
        }
        state = .active(session)
        return []
    }

    /// Plays the offered episode once `session` ended, when it has a stream and may play by itself.
    static func autoplayNext(after session: Session, replacing state: inout State) -> [Effect] {
        guard session.upNextBehavior.autoplay, case .offered(let next) = session.upNext, let stream = next.stream else { return [] }
        return play(stream, of: next, replacing: &state)
    }

    /// Tells the tracker the viewer moved on, then plays `stream` of the offered episode `next`.
    private static func play(_ stream: StreamCandidate, of next: UpNext, replacing state: inout State) -> [Effect] {
        [.report(.movedToNext)] + open(stream, from: .zero, title: next.video.playerTitle(next.show), replacing: &state)
    }
}

extension PlayerFeature.Session {
    /// Offers the tracker's latest answer for the next episode, unless the viewer turned it down.
    mutating func offer(_ next: UpNext?) {
        switch (upNext, next) {
        case (.dismissed, _): break
        case (.notFound, let next?), (.offered, let next?): upNext = .offered(next)
        case (.notFound, nil), (.offered, nil): upNext = .notFound
        }
    }

    /// The episode to offer now: from its notice before the end until the viewer acts on it.
    var upNextCard: UpNext? {
        guard case .offered(let next) = upNext, let lead = upNextBehavior.notice.lead else { return nil }
        let isNear = duration > .zero && duration - position <= lead
        return phase == .ended || isNear ? next : nil
    }
}
