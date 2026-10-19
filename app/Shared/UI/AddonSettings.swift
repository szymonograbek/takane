import SwiftUI

/// The installed add-ons; removing one and installing one by manifest URL.
struct AddonSettings: View {
    @Environment(AppContext.self) private var app
    @State private var removing: InstalledAddon?

    var body: some View {
        let state = app.addons.state
        let note = if case .failed(_, let error) = state.removal { error.message } else { Self.removeHint }
        SettingsPage(title: "Add-ons") {
            SettingsSymbol(name: "puzzlepiece.extension")
        } rows: {
            SettingsSection {
                NavigationLink("Install Add-on") { InstallAddonScreen() }
                    .accessibilityIdentifier("addons.install")
            }
            SettingsSection(title: "Installed", note: note) {
                ForEach(state.installed) { addon in
                    ValueRow(title: addon.name, value: addon.version)
                        .accessibilityIdentifier("addons.row")
                        .contextMenu {
                            if addon.isRemovable {
                                Button("Remove", systemImage: "trash", role: .destructive) { removing = addon }
                            }
                        }
                }
            }
        }
        .confirmationDialog(
            "Remove \(removing?.name ?? "add-on")?", isPresented: Binding { removing != nil } set: { if !$0 { removing = nil } },
            titleVisibility: .visible, presenting: removing
        ) { addon in
            Button("Remove") { app.addons.send(.uninstall(addon.manifestURL)) }
        }
    }

    #if os(tvOS)
    private static let removeHint = "To remove an add-on, press and hold it."
    #else
    private static let removeHint = "To remove an add-on, Control-click it."
    #endif
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
        let upNext = preferences?.upNext ?? .defaults
        SettingsPage(title: "Playback") {
            SettingsSymbol(name: "play.rectangle")
        } rows: {
            SettingsSection(title: "Audio", note: "Used when a stream has it. You can switch during playback.") {
                PreferredLanguagesPicker(
                    title: "Language", none: "Stream Default", selection: preferences?.languages.audio,
                    ids: (primary: "playback.audioLanguage", fallback: "playback.secondAudioLanguage")
                ) {
                    app.preferences.send(.setAudioLanguages($0))
                }
            }
            SettingsSection(title: "Player", note: "Quick presses in a row skip further, up to a minute.") {
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
            }
            SettingsSection(title: "Next Episode", note: "Autoplay needs a matching stream from the same add-on.") {
                NavigationLink {
                    ChoiceList(
                        title: "Up Next Card", symbol: "forward.end",
                        choices: UpNextNotice.allCases.map { (name: $0.name, value: $0) }, selection: upNext.notice
                    ) {
                        app.preferences.send(.setUpNextNotice($0))
                    }
                } label: {
                    LabeledContent("Up Next Card", value: upNext.notice.name)
                }
                .accessibilityIdentifier("playback.upNextNotice")
                Toggle("Autoplay Next Episode", isOn: Binding { upNext.autoplay } set: { autoplay in
                    app.preferences.send(.setAutoplaysNext(autoplay))
                })
                .accessibilityIdentifier("playback.autoplayNext")
            }
            SettingsSection(
                title: "Episodes",
                note: app.preferences.state.failure?.message ?? "Blurs stills and hides summaries of episodes you haven't watched."
            ) {
                Toggle("Hide Spoilers", isOn: Binding { preferences?.hidesSpoilers ?? false } set: { hides in
                    app.preferences.send(.setHidesSpoilers(hides))
                })
                .accessibilityIdentifier("playback.hideSpoilers")
            }
        }
    }
}

private extension SeekStep {
    var name: String { "\(seconds) Seconds" }
}

private extension UpNextNotice {
    var name: String { self == .off ? "Off" : "\(rawValue) Seconds Before End" }
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
