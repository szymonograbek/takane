import SwiftUI

/// The installed add-ons; removing one and installing one by manifest URL.
struct AddonSettings: View {
    @Environment(AppContext.self) private var app
    @State private var removing: InstalledAddon?

    var body: some View {
        let state = app.addons.state
        SettingsPage(title: "Add-ons") {
            SettingsSymbol(name: "puzzlepiece.extension")
        } rows: {
            Section {
                NavigationLink("Install Add-on…") { InstallAddonScreen() }
                    .accessibilityIdentifier("addons.install")
            }
            Section {
                ForEach(state.installed) { addon in
                    ValueRow(title: addon.name, value: addon.version)
                        .accessibilityIdentifier("addons.row")
                        .contextMenu {
                            if addon.isRemovable {
                                Button("Remove", systemImage: "trash", role: .destructive) { removing = addon }
                            }
                        }
                }
            } header: {
                Text("Installed")
            } footer: {
                if case .failed(_, let error) = state.removal {
                    Text(error.message)
                }
            }
        }
        .confirmationDialog(
            "Remove \(removing?.name ?? "add-on")?", isPresented: Binding { removing != nil } set: { if !$0 { removing = nil } },
            titleVisibility: .visible, presenting: removing
        ) { addon in
            Button("Remove", role: .destructive) { app.addons.send(.uninstall(addon.manifestURL)) }
        }
    }
}

/// Typing or pasting a manifest URL, such as a debrid add-on's.
private struct InstallAddonScreen: View {
    @Environment(AppContext.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""

    var body: some View {
        let install = app.addons.state.install
        VStack(spacing: 30) {
            Text("Install Add-on").font(.title2).bold()
            Text("Enter the add-on's manifest URL. It ends in manifest.json.")
                .foregroundStyle(Palette.secondary)
            TextField("https://…/manifest.json", text: $url)
                .textContentType(.URL)
                .onSubmit(submit)
                .accessibilityIdentifier("addons.manifestURL")
            Button(action: submit) {
                if install.isInstalling { ProgressView() } else { Text("Install") }
            }
            .disabled(ManifestURL(url) == nil || install.isInstalling)
            .accessibilityIdentifier("addons.submit")
            if let message = install.message {
                Text(message).foregroundStyle(Palette.secondary).accessibilityIdentifier("addons.status")
            }
        }
        .frame(maxWidth: 900)
        .padding(Metrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas.ignoresSafeArea())
        .onChange(of: install) { _, install in
            if case .installed = install { dismiss() }
        }
    }

    private func submit() {
        guard let manifest = ManifestURL(url) else { return }
        app.addons.send(.install(manifest))
    }
}

/// The languages to pick audio tracks in, how far back and forward skip, and whether unwatched
/// episodes hide spoilers.
struct PlaybackSettings: View {
    @Environment(AppContext.self) private var app

    var body: some View {
        let preferences = app.preferences.state.preferences
        let seekStep = preferences?.seekStep ?? .defaults
        SettingsPage(title: "Playback") {
            SettingsSymbol(name: "play.rectangle")
        } rows: {
            Section {
                PreferredLanguagesPicker(
                    title: "Language", none: "Stream Default", selection: preferences?.languages.audio,
                    ids: (primary: "playback.audioLanguage", fallback: "playback.secondAudioLanguage")
                ) {
                    app.preferences.send(.setAudioLanguages($0))
                }
            } header: {
                Text("Audio")
            } footer: {
                Text("Streams start with audio in this language when they have it, else in the second. You can switch during playback.")
            }
            Section {
                NavigationLink {
                    ChoiceList(
                        title: "Skip Interval", symbol: "goforward",
                        choices: SeekStep.allCases.map { (name: $0.name, value: $0) }, selection: seekStep
                    ) {
                        app.preferences.send(.setSeekStep($0))
                    }
                } label: {
                    LabeledContent("Skip Interval", value: seekStep.name)
                }
                .accessibilityIdentifier("playback.seekStep")
            } header: {
                Text("Player")
            } footer: {
                Text("How far back and forward skip. Quick presses in a row skip further, up to a minute.")
            }
            Section {
                Toggle("Hide Spoilers", isOn: Binding { preferences?.hidesSpoilers ?? false } set: { hides in
                    app.preferences.send(.setHidesSpoilers(hides))
                })
                .accessibilityIdentifier("playback.hideSpoilers")
            } header: {
                Text("Episodes")
            } footer: {
                if case .rejected(let reason)? = app.preferences.state.failure {
                    Text("Couldn't save the change (\(reason)).")
                } else {
                    Text("Episodes you haven't watched blur their picture and leave out their summary.")
                }
            }
        }
    }
}

private extension SeekStep {
    var name: String { "\(seconds) Seconds" }
}

/// A language row and, once a language is chosen, a row for the one to fall back on. Choosing
/// another first language keeps the second.
struct PreferredLanguagesPicker: View {
    let title: String
    /// What the first row reads with no language chosen.
    let none: String
    let selection: PreferredLanguages?
    let ids: (primary: String, fallback: String)
    let choose: (PreferredLanguages?) -> Void

    var body: some View {
        LanguagePicker(title: title, selection: selection?.primary, none: none) {
            choose($0.map { PreferredLanguages(primary: $0, fallback: selection?.fallback) })
        }
        .accessibilityIdentifier(ids.primary)
        if let selection {
            LanguagePicker(title: "Second Language", selection: selection.fallback, none: "None") {
                choose(PreferredLanguages(primary: selection.primary, fallback: $0))
            }
            .accessibilityIdentifier(ids.fallback)
        }
    }
}

/// A row showing the chosen language that opens the full list.
struct LanguagePicker: View {
    let title: String
    let selection: Language?
    let none: String
    let choose: (Language?) -> Void

    var body: some View {
        NavigationLink {
            ChoiceList(
                title: title, symbol: "globe",
                choices: [(name: none, value: nil)] + Language.common.map { (name: $0.displayName, value: $0) },
                selection: selection, choose: choose
            )
        } label: {
            LabeledContent(title, value: selection?.displayName ?? none)
        }
    }
}

/// A pushed list of choices with a checkmark on the current one. Choosing one goes back.
private struct ChoiceList<Value: Hashable>: View {
    @Environment(\.dismiss) private var dismiss
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
            }
        }
    }
}

extension Language {
    /// The languages offered in Settings, as Stremio stores them.
    static let common: [Language] = [
        "eng", "spa", "fre", "ger", "ita", "por", "pol", "dut", "swe", "nor", "dan", "fin", "cze", "hun", "rum",
        "gre", "tur", "rus", "ukr", "ara", "heb", "hin", "jpn", "kor", "chi",
    ].compactMap(Language.init)

    var displayName: String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}
