import Foundation

/// A second subtitle track shown with the first, such as a language the viewer is learning above
/// their own. The two never show the same track, and the timing strip moves only the first.
extension PlayerFeature.Session {
    /// The stream's own tracks that can show second: text, not pictures.
    var secondSubtitleTracks: [MediaTrack] {
        builtInSubtitles.filter { !$0.isImageBased }
    }

    func subtitleChoice(for line: PlayerFeature.SubtitleLine) -> PlayerFeature.SubtitleChoice {
        switch line {
        case .first: subtitleChoice
        case .second: secondSubtitleChoice
        }
    }

    mutating func choose(_ choice: PlayerFeature.SubtitleChoice, for line: PlayerFeature.SubtitleLine) -> [Effect] {
        switch line {
        case .first: chooseSubtitles(choice)
        case .second: chooseSecondSubtitles(choice)
        }
    }

    private mutating func chooseSecondSubtitles(_ choice: PlayerFeature.SubtitleChoice) -> [Effect] {
        guard choice != secondSubtitleChoice, choice == .off || choice != subtitleChoice,
              let effect = effect(showingSecond: choice) else { return [] }
        secondSubtitleChoice = choice
        return [effect]
    }

    /// Turns the second subtitles off once the first show the same track, such as after the viewer
    /// chose it as the first.
    mutating func keepSecondSubtitlesApart() -> [Effect] {
        guard secondSubtitleChoice != .off, secondSubtitleChoice == subtitleChoice else { return [] }
        secondSubtitleChoice = .off
        return [.turnOffSecondSubtitles]
    }

    /// An add-on file shows from the track it was added as; one not added yet is added.
    private func effect(showingSecond choice: PlayerFeature.SubtitleChoice) -> Effect? {
        switch choice {
        case .off:
            return .turnOffSecondSubtitles
        case .builtIn(let track):
            return secondSubtitleTracks.contains { $0.id == track } ? .selectSecond(track) : nil
        case .addon(let id):
            guard let subtitle = addonSubtitle(id) else { return nil }
            guard let track = tracks.first(where: { $0.externalFile == subtitle.url }) else { return .addSecondSubtitles(subtitle) }
            return .selectSecond(track.id)
        }
    }
}

extension AddonSubtitle {
    /// What its track is called: the add-on's description, else the language.
    var title: String {
        label?.rawValue ?? language
    }
}
