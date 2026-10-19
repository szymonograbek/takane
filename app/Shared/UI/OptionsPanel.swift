import SwiftUI

/// A page of choices a transport-bar button opens.
enum PlayerPanel: Hashable {
    case subtitles
    /// One add-on's subtitle files, opened from the subtitles page.
    case addonSubtitles(ManifestURL)
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
        if case .addonSubtitles = self { .subtitles } else { nil }
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
    /// Opens another page, checked when the current choice is on it.
    case link(String, isSelected: Bool, opens: PlayerPanel)
    /// Says why there is nothing to choose, such as an add-on still answering.
    case note(String, detail: String)

    var isSelected: Bool {
        switch self {
        case .choice(_, let isSelected, _), .link(_, let isSelected, _): isSelected
        case .note: false
        }
    }

    /// How focus names this row, the `index`th on its page; nil when it takes no focus.
    func focus(at index: Int) -> PlayerFocus? {
        switch self {
        case .choice: .option(index)
        case .link(_, _, let page): .link(page)
        case .note: nil
        }
    }
}

/// A page of choices above the transport bar, the current one checked. It stands in for a system
/// `Menu`, which on tvOS leaves nothing focused for over a second after it closes.
struct OptionsPanel: View {
    let sections: [PanelSection]
    var focus: FocusState<PlayerFocus?>.Binding
    let choose: (PlayerFeature.Event) -> Void
    let open: (PlayerPanel) -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            list
            ScrollView { list }
        }
        .frame(width: Metrics.playerPanelWidth)
        .padding(Metrics.playerPanelPadding)
        .controlBackground(in: .rect(cornerRadius: Metrics.cornerRadius * 2, style: .continuous))
        // Sized on its own rather than by the button row it overlays; short pages sit at the bottom.
        .frame(height: Metrics.playerPanelMaxHeight, alignment: .bottom)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(numbered.enumerated()), id: \.offset) { _, numbered in
                if let title = numbered.section.title {
                    Text(title).font(.caption).foregroundStyle(Palette.secondary).padding(.top, 8)
                }
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
        case .link(let label, let isSelected, let page):
            Button { open(page) } label: {
                HStack {
                    CheckedLabel(title: label, isChecked: isSelected)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
            .focused(focus, equals: .link(page))
            .accessibilityIdentifier("player.option")
        case .note(let label, let detail):
            LabeledContent(label, value: detail)
                .padding(.horizontal, Metrics.playerPanelPadding)
                .foregroundStyle(Palette.secondary)
        }
    }
}

private extension View {
    /// The panel floats over video as a control, so it takes Liquid Glass where the system has it.
    /// The regular variant keeps its text legible over bright frames.
    @ViewBuilder
    func controlBackground(in shape: some Shape) -> some View {
        if #available(tvOS 26, macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}

/// A row title with a checkmark before it when checked; unchecked titles keep the same indent.
private struct CheckedLabel: View {
    let title: String
    let isChecked: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "checkmark").opacity(isChecked ? 1 : 0)
            Text(title).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}
