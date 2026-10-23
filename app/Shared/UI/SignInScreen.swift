import SwiftUI

/// Sign-in by code: confirm it on a phone or computer, no typing on the remote.
struct SignInScreen: View {
    @Environment(AppContext.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let account = app.account
        VStack(spacing: 36) {
            Text("Sign In to Your Stremio Account").font(.title2).bold()
            switch account.state.signIn {
            case .linking(.loaded(let code)):
                LinkCodeView(code: code)
            case .linking(.failed(let error)):
                failure(error)
            case .linking(.loading), .signingIn:
                ProgressView().frame(height: 300)
            case .idle, .failed:
                // Back from a password attempt: offer a code again.
                Button("Get a Code") { account.send(.startLinking) }.frame(height: 300)
            }
            NavigationLink("Use Email and Password Instead") {
                PasswordSignInScreen()
            }
            .accessibilityIdentifier("signIn.password")
        }
        .padding(Metrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.wash.ignoresSafeArea())
        .onAppear { account.send(.startLinking) }
        .onDisappear {
            if case .linking = account.state.signIn { account.send(.cancel) }
        }
        .dismissWhenSignedIn(account.state.account, dismiss)
    }

    private func failure(_ error: AccountError) -> some View {
        VStack(spacing: 20) {
            Text(error.message).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            Button("Get a New Code") { app.account.send(.startLinking) }
        }
        .frame(height: 300)
    }
}

private struct LinkCodeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let code: LinkCode
    /// Larger than any text style on the Mac, and still growing with the text size.
    @ScaledMetric(relativeTo: .largeTitle) private var codeSize: CGFloat = 64

    var body: some View {
        HStack(spacing: 60) {
            QRCode(text: code.link.rawValue.absoluteString)
                .frame(width: 300, height: 300)
            VStack(alignment: .leading, spacing: 16) {
                Text("Scan with your phone, or go to").foregroundStyle(Palette.secondary)
                Text(code.link.rawValue.host() ?? code.link.rawValue.absoluteString).font(.headline)
                Text("and enter").foregroundStyle(Palette.secondary)
                Text(code.code.rawValue)
                    .font(.system(size: codeSize, weight: .semibold, design: .monospaced))
                    .kerning(12)
                    .accessibilityIdentifier("signIn.code")
                Label("Waiting for you to confirm…", systemImage: "hourglass")
                    .symbolEffect(.rotate.byLayer, options: .repeat(.periodic(delay: 1.5)), isActive: !reduceMotion)
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
            }
        }
    }
}

/// Sign-in with the Stremio account's email and password.
struct PasswordSignInScreen: View {
    @Environment(AppContext.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        let state = app.account.state.signIn
        VStack(spacing: 30) {
            Text("Sign In with Email").font(.title2).bold()
            TextField("Email", text: $email)
                .textContentType(.username)
                .accessibilityIdentifier("signIn.email")
            SecureField("Password", text: $password)
                .textContentType(.password)
                .accessibilityIdentifier("signIn.passwordField")
            if case .failed(let error) = state {
                Text(error.message)
                    .foregroundStyle(Palette.secondary)
                    .accessibilityIdentifier("signIn.error")
            }
            Button {
                guard let address = EmailAddress(email), let secret = Password(password) else { return }
                app.account.send(.signIn(address, secret))
            } label: {
                if case .signingIn = state { ProgressView() } else { Text("Sign In") }
            }
            .disabled(EmailAddress(email) == nil || Password(password) == nil)
            .accessibilityIdentifier("signIn.submit")
        }
        .frame(maxWidth: 800)
        .padding(Metrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.wash.ignoresSafeArea())
        .dismissWhenSignedIn(app.account.state.account, dismiss)
    }
}

private extension View {
    /// Sign-in screens pushed from Settings leave once the account signs in.
    func dismissWhenSignedIn(_ account: Account, _ dismiss: DismissAction) -> some View {
        onChange(of: account) { _, account in
            if case .signedIn = account { dismiss() }
        }
    }
}

extension AccountError {
    var message: String {
        switch self {
        case .rejected(let message): message
        case .linkExpired: "The code expired before it was confirmed."
        case .superseded: "A newer code replaced this one."
        case .unavailable(let reason): "The account service could not be reached (\(reason))."
        }
    }
}
