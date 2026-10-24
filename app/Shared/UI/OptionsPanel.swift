import SwiftUI

/// A page of choices a transport-bar button opens.
enum PlayerPanel: Hashable {
    /// The first subtitles, from the transport bar, or the second, from the first's page.
    case subtitles(PlayerFeature.SubtitleLine)
    /// One add-on's subtitle files, opened from that line's subtitles page.
    case addonSubtitles(ManifestURL, PlayerFeature.SubtitleLine)
    case audio, speed

    /// The transport-bar button this page belongs to, where focus goes back when a choice is made.
    var button: PlayerFocus {
        switch self {
        case .subtitles, .addonSubtitles: .subtitles
        case .audio: .audio
        case .speed: .speed
        }
    }

    /// The page Menu goes back to, or nil when Menu closes the panel.
    var parent: PlayerPanel? {
        switch self {
        case .subtitles(.first), .audio, .speed: nil
        case .subtitles(.second): .subtitles(.first)
        case .addonSubtitles(_, let line): .subtitles(line)
        }
    }

    var title: String {
        switch self {
        case .subtitles, .addonSubtitles: "Subtitles"
        case .audio: "Audio"
        case .speed: "Speed"
        }
    }

    var systemImage: String {
        switch self {
        case .subtitles, .addonSubtitles: "captions.bubble"
        case .audio: "speaker.wave.2"
        case .speed: "gauge.with.dots.needle.50percent"
        }
    }
}

struct PanelSection {
    let title: String?
    let rows: [PanelRow]
}

enum PanelRow {
    /// Sends the event and closes the panel.
    case choice(String, isSelected: Bool, PlayerFeature.Event)
    /// Opens another page, checked when the current choice is on it, and naming the choice made
    /// there as its `value`.
    case link(String, isSelected: Bool, value: String? = nil, opens: PlayerPanel)
    /// Says why there is nothing to choose, such as an add-on still answering.
    case note(String, detail: String)
    /// Opens the subtitle timing strip; `value` is the delay in words.
    case timing(value: String)

    var isSelected: Bool {
        switch self {
        case .choice(_, let isSelected, _), .link(_, let isSelected, _, _): isSelected
        case .note, .timing: false
        }
    }

    /// How focus names this row, the `index`th on its page; nil when it takes no focus.
    func focus(at index: Int) -> PlayerFocus? {
        switch self {
        case .choice, .timing: .option(index)
        case .link(_, _, _, let page): .link(page)
        case .note: nil
        }
    }
}

/// A page of choices above the transport bar, the current one checked, in a `GlassList`.
struct OptionsPanel: View {
    let sections: [PanelSection]
    var focus: FocusState<PlayerFocus?>.Binding
    let choose: (PlayerFeature.Event) -> Void
    let open: (PlayerPanel) -> Void
    let openTiming: () -> Void

    var body: some View {
        GlassList(width: Metrics.playerPanelWidth, maxHeight: Metrics.playerPanelMaxHeight, alignment: .bottom) {
            ForEach(Array(numbered.enumerated()), id: \.offset) { _, numbered in
                if let title = numbered.section.title { GlassListHeader(title) }
                ForEach(Array(numbered.section.rows.enumerated()), id: \.offset) { offset, row in
                    rowView(row, index: numbered.start + offset)
                }
            }
        }
    }

    /// Each section with the page-wide index of its first row, which focus names rows by.
    private var numbered: [(section: PanelSection, start: Int)] {
        var start = 0
        return sections.map { section in
            defer { start += section.rows.count }
            return (section, start)
        }
    }

    @ViewBuilder
    private func rowView(_ row: PanelRow, index: Int) -> some View {
        switch row {
        case .choice(let label, let isSelected, let event):
            Button { choose(event) } label: { CheckedLabel(title: label, isChecked: isSelected) }
                .focused(focus, equals: .option(index))
                .accessibilityIdentifier("player.option")
        case .link(let label, let isSelected, let value, let page):
            Button { open(page) } label: {
                HStack {
                    CheckedLabel(title: label, isChecked: isSelected)
                    if let value { Text(value).foregroundStyle(.secondary).lineLimit(1) }
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
            .focused(focus, equals: .link(page))
            .accessibilityIdentifier(page == .subtitles(.second) ? "player.subtitles.second" : "player.option")
        case .timing(let value):
            Button(action: openTiming) {
                HStack {
                    CheckedLabel(title: "Timing", isChecked: false)
                    Text(value).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .focused(focus, equals: .option(index))
            .accessibilityIdentifier("player.subtitles.timing")
        case .note(let label, let detail):
            LabeledContent(label, value: detail)
                .padding(.horizontal, Metrics.rowPadding)
                .padding(.vertical, Metrics.rowVerticalPadding)
                .foregroundStyle(Palette.secondary)
        }
    }
}
