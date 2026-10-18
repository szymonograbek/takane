import SwiftUI

/// The first launch: sign in to sync with Stremio, or start without an account.
struct WelcomeScreen: View {
    let continueWithoutAccount: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                AppLogo(size: Metrics.welcomeLogoSize)
                Text("Welcome to Takane").font(.largeTitle).bold()
                Text("Sign in with Stremio to bring your add-ons and watch progress. Or start fresh: everything stays on this device.")
                    .font(.body)
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                HStack(spacing: 30) {
                    NavigationLink {
                        SignInScreen()
                    } label: {
                        Label("Sign In with Stremio", systemImage: "person.crop.circle")
                    }
                    .accessibilityIdentifier("welcome.signIn")
                    Button("Continue Without Account", action: continueWithoutAccount)
                        .accessibilityIdentifier("welcome.continue")
                }
                .padding(.top, 20)
            }
            .padding(Metrics.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.wash.ignoresSafeArea())
        }
    }
}
