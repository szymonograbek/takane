import SwiftUI

/// Four categories, laid out like the system's Settings: an emblem on the left, the list on the right.
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
                Section {
                    NavigationLink("Sign In with Stremio") { SignInScreen() }
                        .accessibilityIdentifier("account.signIn")
                } footer: {
                    Text(
                        "Signing in syncs add-ons, library and watch progress with Stremio. Add-ons installed here stay installed; "
                            + "watch progress on this device is replaced by your account's."
                    )
                }
            case .signedIn(let email):
                ValueRow(title: "Email", value: email)
                Button("Sign Out", role: .destructive) { confirmingSignOut = true }
                    .accessibilityIdentifier("account.signOut")
            }
        }
        .confirmationDialog("Sign out of Stremio?", isPresented: $confirmingSignOut) {
            Button("Sign Out", role: .destructive) { app.account.send(.signOut) }
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
            ValueRow(title: "Version", value: Bundle.main.version)
            Section {
                EmptyView()
            } footer: {
                Text("Takane plays streams from your Stremio add-ons. Built on stremio-core and AetherEngine.")
            }
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
