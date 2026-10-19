import SwiftUI

// How a screen offers one of several values: a `ChoiceMenu` in a screen's content, a `ChoiceList`
// for a setting, an `OptionsPanel` in the player. Not the system's pull-down menu on tvOS: SwiftUI's
// `Menu` and UIKit's `UIMenu` keep focus in the menu for the 1.2 s of its closing animation, half a
// second after it is gone from the screen. And not a segmented `Picker`, which on tvOS selects
// whatever segment focus crosses.

/// A button naming the current value that opens its choices below it, the current one checked and
/// focused. On tvOS the choices are a `GlassList` that closes at once, on a choice, on Menu or when
/// focus leaves it, with focus back on the button. The screen draws them with `choiceMenus()` and, while one is open
/// (`isPresented`), disables what lies under it, so focus stays in the list. On macOS it is a
/// system `Menu`.
struct ChoiceMenu<Value: Hashable>: View {
    /// What the choices choose, such as "Sort By".
    let title: String
    /// The button's text, such as "Sort: Name".
    let label: String
    let systemImage: String
    let choices: [(name: String, value: Value)]
    let selection: Value
    @Binding var isPresented: Bool
    let choose: (Value) -> Void

    #if os(tvOS)
    private enum Focus: Hashable {
        case button
        case choice(Value)
    }

    @FocusState private var focus: Focus?

    var body: some View {
        Button {
            isPresented = true
            focus = .choice(selection)
        } label: {
            Label(label, systemImage: systemImage)
        }
        .focused($focus, equals: .button)
        // Focus leaving the choices, up onto the button or anywhere else, closes them.
        .onChange(of: focus) { _, focused in
            if isPresented, !isChoice(focused) { isPresented = false }
        }
        .anchorPreference(key: ChoicePopupKey.self, value: .bounds) { button in
            isPresented ? ChoicePopup(button: button, list: AnyView(list)) : nil
        }
    }

    private var list: some View {
        GlassList(width: Metrics.choiceMenuWidth, maxHeight: Metrics.playerPanelMaxHeight, alignment: .top) {
            GlassListHeader(title)
            ForEach(choices, id: \.value) { choice in
                Button {
                    choose(choice.value)
                    close()
                } label: {
                    CheckedLabel(title: choice.name, isChecked: choice.value == selection)
                }
                .focused($focus, equals: .choice(choice.value))
            }
        }
        .onExitCommand(perform: close)
    }

    private func isChoice(_ focused: Focus?) -> Bool {
        if case .choice = focused { true } else { false }
    }

    private func close() {
        focus = .button
        isPresented = false
    }
    #else
    var body: some View {
        Menu {
            Picker(title, selection: Binding { selection } set: { choose($0) }) {
                ForEach(choices, id: \.value) { Text($0.name).tag($0.value) }
            }
        } label: {
            Label(label, systemImage: systemImage)
        }
    }
    #endif
}

/// The open `ChoiceMenu`'s choices and its button's bounds.
struct ChoicePopup {
    let button: Anchor<CGRect>
    let list: AnyView
}

private struct ChoicePopupKey: PreferenceKey {
    static var defaultValue: ChoicePopup? { nil }

    static func reduce(value: inout ChoicePopup?, nextValue: () -> ChoicePopup?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Draws an open `ChoiceMenu`'s choices below its button, over this view. Apply it to a view that
    /// covers where the choices open. They are laid out in this view's bounds rather than hung from
    /// the button, because the tvOS focus engine does not move between rows that overflow their frame.
    func choiceMenus() -> some View {
        overlayPreferenceValue(ChoicePopupKey.self, alignment: .topLeading) { popup in
            if let popup {
                GeometryReader { proxy in
                    let button = proxy[popup.button]
                    popup.list
                        .padding(.leading, button.minX)
                        .padding(.top, button.maxY + Metrics.headerSpacing)
                }
            }
        }
    }
}

/// Rows of choices floating on Liquid Glass, as tall as they are up to `maxHeight`, past which they
/// scroll. Rows are buttons in `ChoiceRowButtonStyle`; a section title is a `GlassListHeader`. Not a
/// system `List`, which on tvOS reports no size to hug.
struct GlassList<Content: View>: View {
    let width: CGFloat
    let maxHeight: CGFloat
    /// Where a short list sits in `maxHeight`: at the top below what opened it, or at the bottom above it.
    let alignment: VerticalAlignment
    @ViewBuilder let content: () -> Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            panel(rows)
            panel(ScrollView { rows }.scrollClipDisabled())
        }
        .frame(height: maxHeight, alignment: Alignment(horizontal: .leading, vertical: alignment))
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .buttonStyle(ChoiceRowButtonStyle())
    }

    private func panel(_ rows: some View) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cornerRadius * 2, style: .continuous)
        return rows
            .frame(width: width)
            .padding(Metrics.playerPanelPadding)
            // Scrolled rows stop at the panel's edge; the padding leaves room for a focused row's lift.
            .clipShape(shape)
            .controlBackground(in: shape)
    }
}

/// A section title in a `GlassList`.
struct GlassListHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(Palette.secondary)
            .padding(.horizontal, Metrics.rowPadding)
            .padding(.top, Metrics.headerSpacing)
            .padding(.bottom, Metrics.headerSpacing)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A row of a `GlassList`, drawn as a system list row: flat at rest, on a light platter that lifts
/// under focus.
struct ChoiceRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: Configuration

        var body: some View {
            configuration.label
                .padding(.horizontal, Metrics.rowPadding)
                .padding(.vertical, Metrics.rowVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isFocused ? Palette.canvas : Palette.text)
                .background(isFocused ? Palette.text : .clear, in: .capsule)
                .scaleEffect(isFocused && !configuration.isPressed ? 1.04 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 12, y: 6)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

private extension View {
    /// The list floats over content as a control, so it takes Liquid Glass where the system has it.
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
struct CheckedLabel: View {
    let title: String
    let isChecked: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Image(systemName: "checkmark").opacity(isChecked ? 1 : 0)
            Text(title).labelLineLimit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}

/// A pushed list of choices with a checkmark on the current one, which takes focus. Choosing one
/// goes back. For a setting, where a screen of its own leaves room for many values.
struct ChoiceList<Value: Hashable>: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Value?
    let title: String
    let symbol: String
    let choices: [(name: String, value: Value)]
    let selection: Value
    let choose: (Value) -> Void

    var body: some View {
        SettingsPage(title: title) {
            SettingsSymbol(name: symbol)
        } rows: {
            ForEach(choices, id: \.value) { choice in
                Button {
                    choose(choice.value)
                    dismiss()
                } label: {
                    HStack {
                        Text(choice.name)
                        Spacer()
                        if choice.value == selection { Image(systemName: "checkmark") }
                    }
                }
                .focused($focused, equals: choice.value)
            }
        }
        .defaultFocus($focused, selection)
    }
}
