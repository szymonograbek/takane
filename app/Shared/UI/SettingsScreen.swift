import SwiftUI

/// Five categories, laid out like the system's Settings: an emblem on the left, the list on the right.
struct SettingsScreen: View {
    @Environment(AppContext.self) private var app

    var body: some View {
        NavigationStack {
            SettingsPage(title: "Settings") {
                AppLogo(size: Metrics.emblemSize)
            } rows: {
                NavigationLink {
                    AccountSettings()
                } label: {
                    LabeledContent("Account", value: app.account.state.account.email ?? "Not Signed In")
                }
                .accessibilityIdentifier("settings.account")
                NavigationLink {
                    AddonSettings()
                } label: {
                    LabeledContent("Add-ons", value: "\(app.addons.state.installed.count) installed")
                }
                .accessibilityIdentifier("settings.addons")
                NavigationLink("Playback") { PlaybackSettings() }
                    .accessibilityIdentifier("settings.playback")
                NavigationLink {
                    SubtitleSettings()
                } label: {
                    LabeledContent("Subtitles", value: app.preferences.state.preferences?.languages.subtitles?.primary.displayName ?? "Off")
                }
                .accessibilityIdentifier("settings.subtitles")
                NavigationLink("About") { AboutSettings() }
                    .accessibilityIdentifier("settings.about")
            }
        }
    }
}

/// A settings screen: an emblem beside a list of rows.
struct SettingsPage<Emblem: View, Rows: View>: View {
    let title: String
    @ViewBuilder let emblem: () -> Emblem
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        HStack(spacing: Metrics.screenPadding) {
            emblem()
                .frame(maxWidth: .infinity)
            List {
                rows()
                    #if os(tvOS)
                    .listRowInsets(EdgeInsets(top: 0, leading: Metrics.rowPadding, bottom: 0, trailing: Metrics.rowPadding))
                    #endif
            }
            .contentMargins(.top, Metrics.sectionSpacing, for: .scrollContent)
            // Room for a focused row's lift, which the mask below would otherwise cut.
            .safeAreaPadding(.horizontal, Metrics.rowLift)
            // Rows scroll out of sight below the navigation title rather than under it, and off the bottom edge.
            .mask { Rectangle().ignoresSafeArea(edges: .bottom) }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .navigationTitle(title)
        .background(Palette.canvas.ignoresSafeArea())
    }
}

/// A group of rows in a `SettingsPage`, with an optional title above and a short note below.
/// The note sits in the secondary color, so it reads as a hint rather than another row. A title sits
/// closer to its own rows than to the section before.
struct SettingsSection<Rows: View>: View {
    var title: String?
    var note: String?
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        Section {
            rows()
        } header: {
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, Metrics.sectionSpacing)
                    // Clears the first row's lift under focus, which would otherwise cover the title.
                    .padding(.bottom, Metrics.rowLift)
            }
        } footer: {
            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(Palette.secondary)
            }
        }
    }
}

/// A row that shows a value. On tvOS it still takes focus, so it highlights like the other rows,
/// the list scrolls to it, Menu has something to leave from, and a long press opens its context menu.
struct ValueRow: View {
    let title: String
    let value: String

    var body: some View {
        #if os(tvOS)
        Button {} label: { LabeledContent(title, value: value) }
        #else
        LabeledContent(title, value: value)
        #endif
    }
}

/// A large symbol for a settings page's emblem.
struct SettingsSymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: Metrics.emblemSize * 0.5))
            .foregroundStyle(Palette.secondary)
    }
}

private struct AccountSettings: View {
    @Environment(AppContext.self) private var app
    @State private var confirmingSignOut = false

    var body: some View {
        SettingsPage(title: "Account") {
            SettingsSymbol(name: "person.crop.circle")
        } rows: {
            switch app.account.state.account {
            case .anonymous:
                SettingsSection(
                    note: "Sync add-ons, library and watch progress with your Stremio account. "
                        + "Watch progress on this device is replaced by your account's."
                ) {
                    NavigationLink("Sign In with Stremio") { SignInScreen() }
                        .accessibilityIdentifier("account.signIn")
                }
            case .signedIn(let email):
                ValueRow(title: "Email", value: email)
                Button("Sign Out", role: .destructive) { confirmingSignOut = true }
                    .accessibilityIdentifier("account.signOut")
            }
        }
        .confirmationDialog("Sign out of Stremio?", isPresented: $confirmingSignOut) {
            Button("Sign Out") { app.account.send(.signOut) }
        } message: {
            Text("Add-ons and watch progress on this device go back to the defaults.")
        }
    }
}

private struct AboutSettings: View {
    var body: some View {
        SettingsPage(title: "About") {
            AppLogo(size: Metrics.emblemSize)
        } rows: {
            SettingsSection(note: "Takane plays streams from your Stremio add-ons. Built on stremio-core and AetherEngine.") {
                ValueRow(title: "Version", value: Bundle.main.version)
            }
        }
    }
}

extension PreferencesError {
    /// Shown in place of a settings page's last note.
    var message: String {
        switch self {
        case .rejected(let reason): "Couldn't save the change (\(reason))."
        }
    }
}

private extension Bundle {
    var version: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
