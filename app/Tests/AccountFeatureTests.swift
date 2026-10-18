import Foundation
import Testing

struct AccountFeatureTests {
    private let code = LinkCode(code: "K7Q2", link: URL(filePath: "/link"))
    private let email = EmailAddress("anna@example.com").require()
    private let password = Password("secret").require()

    @Test func linkingRequestsACodeThenWaitsForItsConfirmation() {
        var state = AccountFeature.State()
        #expect(AccountFeature.reduce(&state, .startLinking) == [.makeLinkCode])
        #expect(state.signIn == .linking(.loading))
        #expect(AccountFeature.reduce(&state, .linkCodeCreated(.success(code))) == [.awaitConfirmation(code)])
        #expect(state.signIn == .linking(.loaded(code)))
    }

    @Test func anAnswerForAnOlderCodeIsDropped() {
        var state = AccountFeature.State(signIn: .linking(.loaded(code)))
        let older = LinkCode(code: "AAAA", link: URL(filePath: "/link"))
        _ = AccountFeature.reduce(&state, .linkFinished(older, .failure(.linkExpired)))
        #expect(state.signIn == .linking(.loaded(code)))
        _ = AccountFeature.reduce(&state, .linkFinished(code, .failure(.linkExpired)))
        #expect(state.signIn == .linking(.failed(.linkExpired)))
    }

    @Test func switchingToPasswordAbandonsTheCode() {
        var state = AccountFeature.State(signIn: .linking(.loaded(code)))
        let first = AccountFeature.Attempt(email: email, number: 1)
        #expect(AccountFeature.reduce(&state, .signIn(email, password)) == [.cancelLinkCode, .signIn(first, password)])
        #expect(state.signIn == .signingIn(first))
    }

    @Test func aRejectedPasswordIsShownUntilTheNextAttempt() {
        var state = AccountFeature.State()
        _ = AccountFeature.reduce(&state, .signIn(email, password))
        let first = AccountFeature.Attempt(email: email, number: 1)
        _ = AccountFeature.reduce(&state, .signInFinished(first, .failure(.rejected(message: "Wrong password"))))
        #expect(state.signIn == .failed(.rejected(message: "Wrong password")))
        #expect(AccountFeature.reduce(&state, .signIn(email, password)) == [.signIn(AccountFeature.Attempt(email: email, number: 2), password)])
    }

    @Test func aLateAnswerToAnAbandonedAttemptIsDropped() {
        var state = AccountFeature.State()
        _ = AccountFeature.reduce(&state, .signIn(email, password))
        _ = AccountFeature.reduce(&state, .cancel)
        _ = AccountFeature.reduce(&state, .signIn(email, password))
        _ = AccountFeature.reduce(&state, .signInFinished(AccountFeature.Attempt(email: email, number: 1), .failure(.linkExpired)))
        #expect(state.signIn == .signingIn(AccountFeature.Attempt(email: email, number: 2)))
    }

    @Test func signingInEndsTheFlow() {
        var state = AccountFeature.State(signIn: .linking(.loaded(code)))
        _ = AccountFeature.reduce(&state, .accountChanged(.signedIn(email: "anna@example.com")))
        #expect(state == AccountFeature.State(account: .signedIn(email: "anna@example.com"), signIn: .idle))
    }

    @Test func signingOutNeedsAnAccount() {
        var state = AccountFeature.State()
        #expect(AccountFeature.reduce(&state, .signOut).isEmpty)
        state.account = .signedIn(email: "anna@example.com")
        #expect(AccountFeature.reduce(&state, .signOut) == [.signOut])
    }

    @Test func emailAndPasswordParseAtTheBoundary() {
        #expect(EmailAddress(" anna@example.com ")?.rawValue == "anna@example.com")
        #expect(EmailAddress("anna") == nil)
        #expect(EmailAddress("a@b@c") == nil)
        #expect(Password("") == nil)
        #expect("\(password)" == "<password>")
    }
}
