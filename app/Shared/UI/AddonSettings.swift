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
                    if addon.isRemovable {
                        Button { removing = addon } label: { AddonRow(addon: addon) }
                    } else {
                        AddonRow(addon: addon)
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

private struct AddonRow: View {
    let addon: InstalledAddon

    var body: some View {
        LabeledContent(addon.name, value: addon.version)
            .accessibilityIdentifier("addons.row")
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

/// Languages to pick audio and subtitle tracks in.
struct PlaybackSettings: View {
    @Environment(AppContext.self) private var app

    var body: some View {
        let languages = app.preferences.state.playback?.languages ?? .streamDefaults
        SettingsPage(title: "Playback") {
            SettingsSymbol(name: "play.rectangle")
        } rows: {
            Section {
                LanguagePicker(title: "Subtitles", selection: languages.subtitles, none: "Off") {
                    app.preferences.send(.setLanguage(.subtitle, $0))
                }
                LanguagePicker(title: "Audio", selection: languages.audio, none: "Stream Default") {
                    app.preferences.send(.setLanguage(.audio, $0))
                }
            } footer: {
                if case .rejected(let reason)? = app.preferences.state.failure {
                    Text("Couldn't save the change (\(reason)).")
                } else {
                    Text("Streams start with tracks in these languages when they have them. You can switch during playback.")
                }
            }
        }
    }
}

/// A row showing the chosen language that opens the full list.
private struct LanguagePicker: View {
    let title: String
    let selection: Language?
    let none: String
    let choose: (Language?) -> Void

    var body: some View {
        NavigationLink {
            LanguageChoices(title: title, selection: selection, none: none, choose: choose)
        } label: {
            LabeledContent(title, value: selection?.displayName ?? none)
        }
    }
}

private struct LanguageChoices: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let selection: Language?
    let none: String
    let choose: (Language?) -> Void

    var body: some View {
        SettingsPage(title: title) {
            SettingsSymbol(name: "globe")
        } rows: {
            choice(none, language: nil)
            ForEach(Language.common, id: \.self) { choice($0.displayName, language: $0) }
        }
    }

    private func choice(_ name: String, language: Language?) -> some View {
        Button {
            choose(language)
            dismiss()
        } label: {
            HStack {
                Text(name)
                Spacer()
                if language == selection { Image(systemName: "checkmark") }
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
