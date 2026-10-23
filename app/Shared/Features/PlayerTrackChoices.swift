import Foundation

/// The viewer's audio, subtitles and speed: applying a choice, remembering it through the tracker,
/// and restoring what was remembered when the title plays again.
extension PlayerFeature {
    /// Restoring what the viewer chose when this title last played. It applies once and gives way to
    /// any choice the viewer makes first.
    enum Restore: Equatable, Sendable {
        /// Nothing remembered has arrived.
        case awaiting
        /// Remembered choices still to apply, once their tracks are known.
        case pending(TrackChoices)
        /// Applied, overtaken by the viewer's own choice, or nothing to apply.
        case settled
    }

    /// Follows the add-ons' subtitles and what was remembered for `candidate` until another
    /// candidate replaces it.
    @MainActor
    static func follow(
        _ candidate: StreamCandidate,
        playing source: PlaybackSource,
        _ dependencies: Dependencies,
        _ send: @escaping @MainActor (Event) -> Void
    ) async {
        let remembered = dependencies.tracker.remembered(for: candidate, playing: source)
        let subtitles = dependencies.subtitles.subtitles(for: candidate, playing: source)
        let restoring = Task {
            for await choices in remembered {
                send(.remembered(candidate, choices))
            }
        }
        // The subtitles end with the candidate, or when this effect is cancelled.
        for await sources in subtitles {
            send(.subtitlesFound(candidate, sources))
        }
        restoring.cancel()
    }
}

extension PlayerFeature.Session {
    /// The stream's own subtitle tracks, without files added from add-ons.
    var builtInSubtitles: [MediaTrack] {
        tracks.filter { $0.id.kind == .subtitle && $0.externalFile == nil }
    }

    var subtitleChoice: PlayerFeature.SubtitleChoice {
        tracks.first { $0.id.kind == .subtitle && $0.isSelected }.map(subtitleChoice(of:)) ?? .off
    }

    func addonSubtitle(_ id: AddonSubtitle.ID) -> AddonSubtitle? {
        addonSubtitles.first { $0.addon == id.addon }?.subtitles.value?.first { $0.id == id }
    }

    mutating func select(_ id: MediaTrack.ID) -> [Effect] {
        guard let track = tracks.first(where: { $0.id == id }), !track.isSelected else { return [] }
        var choices = self.choices
        switch id.kind {
        case .audio:
            choices.audio = TrackChoices.Track(track)
        case .subtitle:
            choices.subtitles = remembered(subtitleChoice(of: track))
            picksSubtitles = false
        }
        return viewerChose([.select(id)], choices)
    }

    mutating func chooseSubtitles(_ choice: PlayerFeature.SubtitleChoice) -> [Effect] {
        var choices = self.choices
        choices.subtitles = remembered(choice)
        picksSubtitles = false
        return viewerChose(effects(choosing: choice), choices)
    }

    mutating func setSpeed(_ speed: PlaybackSpeed) -> [Effect] {
        var choices = self.choices
        choices.speed = speed
        return viewerChose(speed == self.speed ? [] : [.setSpeed(speed)], choices)
    }

    /// Restores `choices`, remembered for this title, unless they already arrived or the viewer chose first.
    mutating func restoreRemembered(_ choices: TrackChoices) -> [Effect] {
        guard restore == .awaiting else { return [] }
        restore = .pending(choices)
        return continueRestore()
    }

    /// Takes what the add-ons offer for this stream, which a remembered add-on file may be waiting on.
    mutating func receive(_ sources: [SubtitleSource]) -> [Effect] {
        addonSubtitles = sources
        return continueRestore() + preferredSubtitles()
    }

    /// Shows subtitles in the most preferred language that has any, until the viewer chooses: the
    /// stream's own track, which the engine selects by itself, else the first file the add-ons offer,
    /// in their order. Add-ons that time files to this stream put the best one first and may answer
    /// again once they know the file, so a later answer can replace an earlier pick. An add-on still
    /// answering holds the pick, since an earlier one in the order may yet offer a file.
    func preferredSubtitles() -> [Effect] {
        guard picksSubtitles, let languages = subtitleLanguages, !tracks.isEmpty else { return [] }
        if case .pending(let choices) = restore, choices.subtitles != nil { return [] }
        for language in languages.inPreferenceOrder {
            // A forced track only translates signs and foreign lines.
            if builtInSubtitles.contains(where: { !$0.isForced && $0.language.flatMap(Language.init) == language }) { return [] }
            for source in addonSubtitles {
                switch source.subtitles {
                case .loading:
                    return []
                case .loaded(let files):
                    if let file = files.first(where: { Language($0.language) == language }) {
                        return effects(choosing: .addon(file.id))
                    }
                case .failed:
                    continue
                }
            }
        }
        return []
    }

    /// Applies what the known tracks allow of the remembered choices. An add-on file waits until the
    /// add-ons answer; one none of them offers is dropped.
    mutating func continueRestore() -> [Effect] {
        guard case .pending(let choices) = restore, !tracks.isEmpty else { return [] }
        restore = .settled
        var effects: [Effect] = []
        if let audio = choices.audio, let track = audio.match(in: tracks.filter { $0.id.kind == .audio }), !track.isSelected {
            effects.append(.select(track.id))
        }
        switch choices.subtitles {
        case nil:
            break
        case .builtIn(let saved):
            if let track = saved.match(in: builtInSubtitles) {
                picksSubtitles = false
                if !track.isSelected { effects.append(.select(track.id)) }
            }
        case .addon(let url, _):
            if let offered = addonSubtitles.lazy.compactMap(\.subtitles.value).joined().first(where: { $0.url == url }) {
                picksSubtitles = false
                effects += self.effects(choosing: .addon(offered.id))
            } else if addonSubtitles.isEmpty || addonSubtitles.contains(where: { !$0.subtitles.isSettled }) {
                restore = .pending(TrackChoices(subtitles: choices.subtitles))
            }
        }
        if let speed = choices.speed, speed != self.speed {
            effects.append(.setSpeed(speed))
        }
        return effects
    }

    /// The choice that selecting `track`, a subtitle track, makes.
    func subtitleChoice(of track: MediaTrack) -> PlayerFeature.SubtitleChoice {
        guard let file = track.externalFile else { return .builtIn(track.id) }
        let subtitle = addonSubtitles.lazy.compactMap(\.subtitles.value).joined().first { $0.url == file }
        return subtitle.map { .addon($0.id) } ?? .off
    }

    /// What plays now, as the tracker remembers it.
    private var choices: TrackChoices {
        TrackChoices(
            audio: tracks.first { $0.id.kind == .audio && $0.isSelected }.map(TrackChoices.Track.init),
            subtitles: remembered(subtitleChoice),
            speed: speed
        )
    }

    private func remembered(_ choice: PlayerFeature.SubtitleChoice) -> TrackChoices.Subtitles? {
        switch choice {
        case .off: nil
        case .builtIn(let id): tracks.first { $0.id == id }.map { .builtIn(TrackChoices.Track($0)) }
        case .addon(let id): addonSubtitle(id).map { .addon($0.url, language: $0.language) }
        }
    }

    /// A choice that changes playback is remembered, and settles the restore so the remembered
    /// choices cannot undo it.
    private mutating func viewerChose(_ effects: [Effect], _ choices: TrackChoices) -> [Effect] {
        guard !effects.isEmpty else { return [] }
        restore = .settled
        return effects + [.report(.choices(choices))]
    }

    /// An add-on file plays from the track it was added as; one not added yet is added.
    private func effects(choosing choice: PlayerFeature.SubtitleChoice) -> [Effect] {
        switch choice {
        case .off:
            return subtitleChoice == .off ? [] : [.turnOffSubtitles]
        case .builtIn(let track):
            return tracks.contains { $0.id == track && $0.externalFile == nil && !$0.isSelected } ? [.select(track)] : []
        case .addon(let id):
            guard let subtitle = addonSubtitle(id) else { return [] }
            guard let track = tracks.first(where: { $0.externalFile == subtitle.url }) else { return [.addSubtitles(subtitle)] }
            return track.isSelected ? [] : [.select(track.id)]
        }
    }
}

extension TrackChoices.Track {
    init(_ track: MediaTrack) {
        self.init(number: track.id.number, language: track.language)
    }

    /// The track of `tracks` this one names: the same number in the same language, else the first in
    /// that language.
    func match(in tracks: [MediaTrack]) -> MediaTrack? {
        tracks.first { $0.id.number == number && $0.language == language }
            ?? language.flatMap { language in tracks.first { $0.language == language } }
    }
}
