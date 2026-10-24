import SwiftUI

/// The options panel's subtitle pages. Each lists Off, the stream's own tracks and the add-ons'
/// files; the first's also holds its timing and a link to the second's, which leaves out what the
/// first shows and the tracks drawn as pictures.
struct SubtitlePages {
    let session: PlayerFeature.Session
    /// Files in these languages lead an add-on's page, most preferred first.
    let preferredLanguages: [Language]

    func sections(for line: PlayerFeature.SubtitleLine) -> [PanelSection] {
        let choice = session.subtitleChoice(for: line)
        let builtIn = [PanelRow.choice("Off", isSelected: choice == .off, .chooseSubtitles(.off, for: line))]
            + tracks(for: line).map { track in
                .choice(track.label, isSelected: choice == .builtIn(track.id), .chooseSubtitles(.builtIn(track.id), for: line))
            }
        let top = line == .first ? topRows : []
        guard !session.addonSubtitles.isEmpty || !top.isEmpty else { return [PanelSection(title: nil, rows: builtIn)] }
        let addons = session.addonSubtitles.isEmpty ? [] : [
            PanelSection(title: "Add-ons", rows: session.addonSubtitles.map { addonRow($0, for: line) }),
        ]
        return (top.isEmpty ? [] : [PanelSection(title: nil, rows: top)]) + [PanelSection(title: "Built-in", rows: builtIn)] + addons
    }

    /// One add-on's files, grouped by language.
    func sections(for addon: ManifestURL, as line: PlayerFeature.SubtitleLine) -> [PanelSection] {
        let files = (session.addonSubtitles.first { $0.addon == addon }?.subtitles.value ?? []).filter { file in
            line == .first || session.subtitleChoice != .addon(file.id)
        }
        return languageGroups(files).map { group in
            let name = languageName(group.language)
            return PanelSection(title: name, rows: group.files.enumerated().map { index, file in
                .choice(
                    file.label?.rawValue ?? "\(name) \(index + 1)",
                    isSelected: session.subtitleChoice(for: line) == .addon(file.id), .chooseSubtitles(.addon(file.id), for: line)
                )
            })
        }
    }

    private func tracks(for line: PlayerFeature.SubtitleLine) -> [MediaTrack] {
        switch line {
        case .first: session.builtInSubtitles
        case .second: session.secondSubtitleTracks.filter { session.subtitleChoice != .builtIn($0.id) }
        }
    }

    /// Timing and Reset Timing while subtitles show, then Second Subtitles while there is any to show.
    private var topRows: [PanelRow] {
        let delay = session.subtitleDelay
        let timing: [PanelRow] = session.subtitleChoice == .off ? [] : [.timing(value: delay.label)]
            + (delay == .zero ? [] : [.choice("Reset Timing", isSelected: false, .subtitleTiming(.reset))])
        let hasSecond = !session.secondSubtitleTracks.isEmpty || !session.addonSubtitles.isEmpty
        return timing + (hasSecond ? [.link("Second Subtitles", isSelected: false, value: secondValue, opens: .subtitles(.second))] : [])
    }

    /// The second subtitles' language, short enough to sit beside the row's name, or Off.
    private var secondValue: String {
        switch session.secondSubtitleChoice {
        case .off: "Off"
        case .builtIn(let id): session.tracks.first { $0.id == id }.map { $0.language.map(languageName) ?? $0.label } ?? "Off"
        case .addon(let id): session.addonSubtitle(id).map { languageName($0.language) } ?? "Off"
        }
    }

    /// An add-on's files open on their own page; until it has some, the row says why not.
    private func addonRow(_ source: SubtitleSource, for line: PlayerFeature.SubtitleLine) -> PanelRow {
        switch source.subtitles {
        case .loading: return .note(source.addonName.rawValue, detail: "Loading…")
        case .failed: return .note(source.addonName.rawValue, detail: "Unavailable")
        case .loaded(let files) where files.isEmpty: return .note(source.addonName.rawValue, detail: "None Found")
        case .loaded:
            let isChosen = if case .addon(let id) = session.subtitleChoice(for: line) { id.addon == source.addon } else { false }
            return .link(source.addonName.rawValue, isSelected: isChosen, opens: .addonSubtitles(source.addon, line))
        }
    }

    /// Files grouped by language in the add-on's order, the preferred languages first.
    private func languageGroups(_ files: [AddonSubtitle]) -> [(language: String, files: [AddonSubtitle])] {
        var groups: [(language: String, files: [AddonSubtitle])] = []
        for file in files {
            if let index = groups.firstIndex(where: { $0.language == file.language }) {
                groups[index].files.append(file)
            } else {
                groups.append((file.language, [file]))
            }
        }
        for language in preferredLanguages.reversed() {
            if let index = groups.firstIndex(where: { Language($0.language) == language }) {
                groups.insert(groups.remove(at: index), at: 0)
            }
        }
        return groups
    }
}
