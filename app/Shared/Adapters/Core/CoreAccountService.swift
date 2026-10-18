import Foundation
import os

/// The Stremio account through core's profile and its `link` model.
///
/// Core replaces the profile's add-ons with the account's and resets its settings when signing
/// in. This adapter installs the add-ons added while signed out again and restores the settings,
/// as `AccountService` promises.
struct CoreAccountService: AccountService {
    let runtime: CoreRuntime

    /// How often to ask whether a code was confirmed, and for how long.
    private static let linkPollInterval = Duration.seconds(3)
    private static let linkLifetime = Duration.seconds(600)

    func account() -> AsyncStream<Account> {
        runtime.observe(.ctx, as: CtxState.self) { ctx in
            ctx.profile.auth.map { .signedIn(email: $0.user.email) } ?? .anonymous
        }
    }

    func makeLinkCode() async throws(AccountError) -> LinkCode {
        // The state before the load is probed first; only what follows this load's `Loading` answers it.
        let loaded = OSAllocatedUnfairLock(initialState: false)
        do {
            return try await runtime.request(
                .load(.link), to: .link, observing: .link, as: LinkState.self, timeout: .seconds(20)
            ) { state -> Probe<LinkCode, AccountError> in
                switch state.code {
                case .loading:
                    loaded.withLock { $0 = true }
                    return .pending
                case .ready(let code) where loaded.withLock({ $0 }):
                    guard let link = URL(string: code.link) else { return .failed(.unavailable(reason: "invalid link \(code.link)")) }
                    return .done(LinkCode(code: code.code, link: link))
                case .failed(let error) where loaded.withLock({ $0 }):
                    return .failed(.unavailable(reason: Self.message(error)))
                case .none, .ready, .failed:
                    return .pending
                }
            }
        } catch {
            throw Self.accountError(error)
        }
    }

    func signIn(confirming code: LinkCode) async throws(AccountError) {
        let deadline = ContinuousClock.now + Self.linkLifetime
        while ContinuousClock.now < deadline {
            guard !Task.isCancelled, (try? linkState().code?.readyContent?.code) == code.code else { throw .superseded }
            try dispatch(.link(.readData), to: .link)
            try? await Task.sleep(for: Self.linkPollInterval)
            // Before confirmation the API answers with an error; only a key means confirmed.
            let state = try linkState()
            if state.code?.readyContent?.code == code.code, let authKey = state.data?.readyContent?.authKey {
                try await authenticate(.loginWithToken(authKey))
                runtime.dispatchLogged(.unload, to: .link)
                return
            }
        }
        throw .linkExpired
    }

    func cancelLinkCode() {
        runtime.dispatchLogged(.unload, to: .link)
    }

    func signIn(email: EmailAddress, password: Password) async throws(AccountError) {
        try await authenticate(.login(email: email.rawValue, password: password.rawValue))
    }

    func signOut() {
        runtime.dispatchLogged(.ctx(.logout))
    }

    /// Signs in, then restores what the signed-out profile had: the add-ons it added and its settings.
    private func authenticate(_ request: CoreAction.Authentication) async throws(AccountError) {
        let before: Profile
        do {
            before = try runtime.state(.ctx, as: CtxState.self).profile
        } catch {
            throw .unavailable(reason: "\(error)")
        }
        guard before.auth == nil else { throw .rejected(message: "Already signed in. Sign out first.") }
        let failures = runtime.events()
        let signedIn = runtime.observe(.ctx, as: CtxState.self) { $0.profile.auth?.user.email }
        try dispatch(.ctx(.authenticate(request)))
        let outcome = await withTaskGroup(of: Result<Profile, AccountError>?.self) { group in
            group.addTask {
                for await email in signedIn where email != nil {
                    if let profile = try? runtime.state(.ctx, as: CtxState.self).profile { return .success(profile) }
                }
                return nil
            }
            group.addTask {
                for await event in failures {
                    if let message = Self.authenticationFailure(event) { return .failure(.rejected(message: message)) }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(60))
                return .failure(.unavailable(reason: "timed out"))
            }
            defer { group.cancelAll() }
            for await case let outcome? in group {
                return outcome
            }
            return .failure(.unavailable(reason: "cancelled"))
        }
        let after = try outcome.get()
        // Official add-ons the account lacks were removed on purpose; only ones the user added come back.
        let kept = Set(after.addons.map(\.transportUrl))
        for addon in before.addons where !kept.contains(addon.transportUrl) && !(addon.flags?.isOfficial ?? false) {
            Log.core.info("keeping \(addon.manifest.name) after sign-in")
            runtime.dispatchLogged(.ctx(.installAddon(descriptor: addon.descriptor)))
        }
        runtime.dispatchLogged(.ctx(.updateSettings(before.settings)))
    }

    private func linkState() throws(AccountError) -> LinkState {
        do {
            return try runtime.state(.link, as: LinkState.self)
        } catch {
            throw .unavailable(reason: "\(error)")
        }
    }

    private func dispatch(_ action: CoreAction, to field: CoreField? = nil) throws(AccountError) {
        do {
            try runtime.dispatch(action, to: field)
        } catch {
            throw .unavailable(reason: "\(error)")
        }
    }

    /// The API's message when `event` reports a failed sign-in.
    private static func authenticationFailure(_ event: CoreEvent) -> String? {
        guard event.name == "Error", case .object(let args) = event.args,
              case .object(let source)? = args["source"], source["event"] == .string("UserAuthenticated")
        else { return nil }
        return args["error"].map(message) ?? "Sign-in failed."
    }

    /// core serializes its errors as `{"type": …, "message": …}` or wraps them in `content`.
    private static func message(_ error: JSONValue) -> String {
        guard case .object(let fields) = error else { return error.compactDescription }
        if case .string(let message)? = fields["message"] { return message }
        if let content = fields["content"] { return message(content) }
        return error.compactDescription
    }

    private static func accountError(_ error: CoreRequestError<AccountError>) -> AccountError {
        switch error {
        case .rejected(let error): .unavailable(reason: "\(error)")
        case .timedOut: .unavailable(reason: "timed out")
        case .failed(let error): error
        }
    }
}
