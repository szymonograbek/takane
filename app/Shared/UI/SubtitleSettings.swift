import SwiftUI

/// The languages streams start with subtitles in, and how text subtitles look, beside a live preview.
struct SubtitleSettings: View {
    @Environment(AppContext.self) private var app
    @State private var confirmingReset = false

    var body: some View {
        let languages = app.preferences.state.playback?.languages.subtitles
        let style = app.preferences.state.playback?.subtitleStyle ?? .defaults
        SettingsPage(title: "Subtitles") {
            SubtitlePreview(style: style)
        } rows: {
            Section {
                PreferredLanguagesPicker(
                    title: "Language", none: "Off", selection: languages,
                    ids: (primary: "subtitles.language", fallback: "subtitles.secondLanguage")
                ) {
                    app.preferences.send(.setSubtitleLanguages($0))
                }
            } header: {
                Text("Language")
            } footer: {
                Text("Streams start with subtitles in this language when they have them, else in the second.")
            }
            Section {
                styleRows(style)
            } header: {
                Text("Style")
            } footer: {
                if case .rejected(let reason)? = app.preferences.state.failure {
                    Text("Couldn't save the change (\(reason)).")
                } else {
                    Text("Applies to text subtitles; picture-based ones keep their look. File styling keeps a subtitle file's colors, fonts and positions.")
                }
            }
        }
        .confirmationDialog("Reset the subtitle style?", isPresented: $confirmingReset) {
            Button("Reset Style", role: .destructive) { app.preferences.send(.setSubtitleStyle(.defaults)) }
        } message: {
            Text("Size, font, colors, opacity, position and file styling go back to Stremio's defaults.")
        }
    }

    @ViewBuilder
    private func styleRows(_ style: SubtitleStyle) -> some View {
        let save = { (edited: SubtitleStyle) in app.preferences.send(.setSubtitleStyle(edited)) }
        StylePicker(setting: .size, style: style, choose: save)
        StylePicker(setting: .font, style: style, choose: save)
        Toggle("Bold", isOn: Binding { style.isBold } set: { isBold in
            var bold = style
            bold.isBold = isBold
            save(bold)
        })
        .accessibilityIdentifier("subtitles.bold")
        Toggle("Subtitle File Styling", isOn: Binding { style.usesFileStyling } set: { usesFileStyling in
            var styled = style
            styled.usesFileStyling = usesFileStyling
            save(styled)
        })
        .accessibilityIdentifier("subtitles.fileStyling")
        StylePicker(setting: .textColor, style: style, choose: save)
        StylePicker(setting: .outlineColor, style: style, choose: save)
        StylePicker(setting: .backgroundColor, style: style, choose: save)
        StylePicker(setting: .opacity, style: style, choose: save)
        StylePicker(setting: .position, style: style, choose: save)
        Button("Reset Style", role: .destructive) { confirmingReset = true }
            .disabled(style == .defaults)
            .accessibilityIdentifier("subtitles.reset")
    }
}

/// Sample dialogue in `style` over a scene with light and dark areas, drawn by the player's own overlay.
/// Its second line is styled as a file would, so turning file styling on shows a color.
struct SubtitlePreview: View {
    private static let sample = SubtitleCue.text(SubtitleText(runs: [
        SubtitleRun(text: "I thought you'd never get here.\n"),
        SubtitleRun(text: "Come on, the boat leaves at dawn.", isItalic: true, color: SubtitleColor(red: 140, green: 220, blue: 255)),
    ], placement: nil))

    let style: SubtitleStyle

    var body: some View {
        Palette.previewScene
            .overlay {
                SubtitleOverlay(cues: [Self.sample], videoSize: VideoSize(width: 1_920, height: 1_080), style: style)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(.rect(cornerRadius: Metrics.cornerRadius))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Subtitle Preview")
            .accessibilityIdentifier("subtitles.preview")
    }
}

/// One setting of the style: its row's title and id, where it lives in the style and its choices.
private struct StyleSetting<Value: Hashable> {
    let title: String
    let id: String
    let path: WritableKeyPath<SubtitleStyle, Value>
    let options: [StyleOption<Value>]
}

private struct StyleOption<Value: Hashable>: Identifiable {
    let name: String
    let value: Value
    /// Shown beside the name of a color.
    var swatch: SubtitleColor?

    var id: String { name }
}

/// A row showing the setting's current choice that opens the list of choices. A value no choice
/// matches, set by another Stremio app, reads as Custom.
private struct StylePicker<Value: Hashable>: View {
    let setting: StyleSetting<Value>
    let style: SubtitleStyle
    let choose: (SubtitleStyle) -> Void

    var body: some View {
        let current = style[keyPath: setting.path]
        NavigationLink {
            StyleChoices(setting: setting, style: style, choose: choose)
        } label: {
            LabeledContent(setting.title, value: setting.options.first { $0.value == current }?.name ?? "Custom")
        }
        .accessibilityIdentifier(setting.id)
    }
}

/// The choices for one setting beside the preview, which shows the focused choice applied.
private struct StyleChoices<Value: Hashable>: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Value?
    let setting: StyleSetting<Value>
    let style: SubtitleStyle
    let choose: (SubtitleStyle) -> Void

    var body: some View {
        let current = style[keyPath: setting.path]
        SettingsPage(title: setting.title) {
            SubtitlePreview(style: applying(focused ?? current))
        } rows: {
            ForEach(setting.options) { option in
                Button {
                    choose(applying(option.value))
                    dismiss()
                } label: {
                    HStack {
                        if let swatch = option.swatch { Swatch(color: swatch) }
                        Text(option.name)
                        Spacer()
                        if option.value == current { Image(systemName: "checkmark") }
                    }
                }
                .focused($focused, equals: option.value)
            }
        }
        .defaultFocus($focused, current)
    }

    private func applying(_ value: Value) -> SubtitleStyle {
        var changed = style
        changed[keyPath: setting.path] = value
        return changed
    }
}

private struct Swatch: View {
    let color: SubtitleColor

    var body: some View {
        Circle()
            .fill(Color(color))
            .strokeBorder(Palette.secondary, lineWidth: 1)
            .frame(width: Metrics.swatchSize, height: Metrics.swatchSize)
    }
}

extension StyleSetting<Percent> {
    static var size: Self { percents("Size", id: "subtitles.size", path: \.size, [75, 100, 125, 150, 175, 200, 250]) }
    static var opacity: Self { percents("Opacity", id: "subtitles.opacity", path: \.opacity, [25, 50, 75, 100]) }
    static var position: Self { percents("Position", id: "subtitles.position", path: \.bottomOffset, [0, 5, 10, 15, 20, 25]) }

    private static func percents(_ title: String, id: String, path: WritableKeyPath<SubtitleStyle, Percent>, _ values: [UInt8]) -> Self {
        StyleSetting(title: title, id: id, path: path, options: values.map { StyleOption(name: "\($0)%", value: Percent($0)) })
    }
}

extension StyleSetting<SubtitleFont> {
    static var font: Self {
        StyleSetting(title: "Font", id: "subtitles.font", path: \.font, options: SubtitleFont.allCases.map { font in
            let name = switch font {
            case .system: "System"
            case .rounded: "Rounded"
            case .serif: "Serif"
            case .monospaced: "Monospaced"
            }
            return StyleOption(name: name, value: font)
        })
    }
}

extension StyleSetting<SubtitleColor> {
    static var textColor: Self {
        colors("Text Color", id: "subtitles.textColor", path: \.textColor, [
            ("White", .white),
            ("Yellow", SubtitleColor(red: 255, green: 230, blue: 0)),
            ("Cyan", SubtitleColor(red: 0, green: 230, blue: 255)),
            ("Green", SubtitleColor(red: 0, green: 230, blue: 60)),
            ("Black", .black),
        ])
    }

    static var outlineColor: Self {
        colors("Outline Color", id: "subtitles.outlineColor", path: \.outlineColor, [
            ("None", .transparent), ("Black", .black), ("Gray", SubtitleColor(red: 128, green: 128, blue: 128)), ("White", .white),
        ])
    }

    static var backgroundColor: Self {
        colors("Background Color", id: "subtitles.backgroundColor", path: \.backgroundColor, [
            ("None", .transparent), ("Translucent Black", SubtitleColor(red: 0, green: 0, blue: 0, alpha: 128)), ("Black", .black),
        ])
    }

    private static func colors(
        _ title: String, id: String, path: WritableKeyPath<SubtitleStyle, SubtitleColor>, _ presets: [(String, SubtitleColor)]
    ) -> Self {
        StyleSetting(title: title, id: id, path: path, options: presets.map { StyleOption(name: $0.0, value: $0.1, swatch: $0.1) })
    }
}

private extension SubtitleColor {
    static let white = SubtitleColor(red: 255, green: 255, blue: 255)
    static let black = SubtitleColor(red: 0, green: 0, blue: 0)
    static let transparent = SubtitleColor(red: 0, green: 0, blue: 0, alpha: 0)
}
