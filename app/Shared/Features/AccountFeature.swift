/// The signed-in account, and signing in by code or by password.
enum AccountFeature: Feature {
    struct Dependencies: Sendable {
        let account: any AccountService
    }

    /// One press of Sign In, so a late answer to an earlier press is told apart.
    struct Attempt: Hashable, Sendable {
        let email: EmailAddress
        let number: Int
    }

    enum SignIn: Equatable, Sendable {
        case idle
        /// A code is requested, shown while waiting for confirmation, or failed.
        case linking(Remote<LinkCode, AccountError>)
        case signingIn(Attempt)
        case failed(AccountError)
    }

    struct State: Equatable, Sendable {
        var account = Account.anonymous
        var signIn = SignIn.idle
        var attempts = 0
    }

    enum Event: Sendable {
        case accountChanged(Account)
        case startLinking
        case linkCodeCreated(Result<LinkCode, AccountError>)
        case linkFinished(LinkCode, Result<Void, AccountError>)
        case signIn(EmailAddress, Password)
        case signInFinished(Attempt, Result<Void, AccountError>)
        /// Leaves sign-in, abandoning a code being waited on.
        case cancel
        case signOut
    }

    enum Effect: Equatable, Sendable {
        /// Start it once, when the store is created.
        case observeAccount
        case makeLinkCode
        case awaitConfirmation(LinkCode)
        case cancelLinkCode
        case signIn(Attempt, Password)
        case signOut
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch (state.signIn, event) {
        case (_, .accountChanged(let account)):
            state.account = account
            if case .signedIn = account { state.signIn = .idle }
            return []

        case (.signingIn, .startLinking):
            return []
        case (.linking, .startLinking), (.idle, .startLinking), (.failed, .startLinking):
            state.signIn = .linking(.loading)
            return [.makeLinkCode]

        case (.linking(.loading), .linkCodeCreated(.success(let code))):
            state.signIn = .linking(.loaded(code))
            return [.awaitConfirmation(code)]
        case (.linking(.loading), .linkCodeCreated(.failure(let error))):
            state.signIn = .linking(.failed(error))
            return []
        case (_, .linkCodeCreated):
            return []

        case (.linking(.loaded(let current)), .linkFinished(let code, let result)) where current == code:
            switch result {
            case .success: state.signIn = .idle
            case .failure(let error): state.signIn = .linking(.failed(error))
            }
            return []
        case (_, .linkFinished):
            return []

        case (.signingIn, .signIn):
            return []
        case (.linking, .signIn(let email, let password)):
            let attempt = state.nextAttempt(email)
            state.signIn = .signingIn(attempt)
            return [.cancelLinkCode, .signIn(attempt, password)]
        case (.idle, .signIn(let email, let password)), (.failed, .signIn(let email, let password)):
            let attempt = state.nextAttempt(email)
            state.signIn = .signingIn(attempt)
            return [.signIn(attempt, password)]

        case (.signingIn(let pending), .signInFinished(let attempt, let result)) where pending == attempt:
            switch result {
            case .success: state.signIn = .idle
            case .failure(let error): state.signIn = .failed(error)
            }
            return []
        case (_, .signInFinished):
            return []

        case (.linking, .cancel):
            state.signIn = .idle
            return [.cancelLinkCode]
        case (.idle, .cancel), (.signingIn, .cancel), (.failed, .cancel):
            // A password sign-in in flight still finishes; its answer is dropped.
            state.signIn = .idle
            return []

        case (_, .signOut):
            guard case .signedIn = state.account else { return [] }
            return [.signOut]
        }
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        let service = dependencies.account
        switch effect {
        case .observeAccount:
            for await account in service.account() {
                send(.accountChanged(account))
            }
        case .makeLinkCode:
            do {
                send(.linkCodeCreated(.success(try await service.makeLinkCode())))
            } catch {
                send(.linkCodeCreated(.failure(error)))
            }
        case .awaitConfirmation(let code):
            do {
                try await service.signIn(confirming: code)
                send(.linkFinished(code, .success(())))
            } catch {
                send(.linkFinished(code, .failure(error)))
            }
        case .cancelLinkCode:
            service.cancelLinkCode()
        case .signIn(let attempt, let password):
            do {
                try await service.signIn(email: attempt.email, password: password)
                send(.signInFinished(attempt, .success(())))
            } catch {
                send(.signInFinished(attempt, .failure(error)))
            }
        case .signOut:
            service.signOut()
        }
    }
}

private extension AccountFeature.State {
    mutating func nextAttempt(_ email: EmailAddress) -> AccountFeature.Attempt {
        attempts += 1
        return AccountFeature.Attempt(email: email, number: attempts)
    }
}

extension Account {
    var email: Redacted<String>? {
        if case .signedIn(let email) = self { email } else { nil }
    }
}
