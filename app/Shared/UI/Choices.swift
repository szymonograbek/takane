import SwiftUI

// How a screen offers one of several values. Not a system `Menu`, which on tvOS leaves nothing
// focused for over a second after it closes, and not a segmented `Picker`, which on tvOS selects
// whatever segment focus crosses. The player offers its choices in an `OptionsPanel`.

/// A few values as a row of buttons in a screen's content, the current one checked. Choosing is a
/// click and nothing opens, so focus stays on the value chosen.
struct ChoiceRow<Value: Hashable>: View {
    let title: String
    let choices: [(name: String, value: Value)]
    let selection: Value
    let choose: (Value) -> Void

    var body: some View {
        HStack(spacing: Metrics.headerSpacing) {
            ForEach(choices, id: \.value) { choice in
                let isSelected = choice.value == selection
                Button { choose(choice.value) } label: {
                    HStack(spacing: 12) {
                        if isSelected { Image(systemName: "checkmark") }
                        Text(choice.name)
                    }
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// A pushed list of choices with a checkmark on the current one, which takes focus. Choosing one
/// goes back. For a setting, or more values than fit in a `ChoiceRow`.
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
