import Foundation
import Testing

struct AccountFeatureTests {
    private let code = LinkCode(code: Redacted("K7Q2"), link: Redacted(URL(filePath: "/link")))
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
        let older = LinkCode(code: Redacted("AAAA"), link: Redacted(URL(filePath: "/link")))
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
        _ = AccountFeature.reduce(&state, .accountChanged(.signedIn(email: Redacted("anna@example.com"), hasPremium: false, trakt: .linked)))
        #expect(state == AccountFeature.State(account: .signedIn(email: Redacted("anna@example.com"), hasPremium: false, trakt: .linked), signIn: .idle))
    }

    @Test func signingOutNeedsAnAccount() {
        var state = AccountFeature.State()
        #expect(AccountFeature.reduce(&state, .signOut).isEmpty)
        state.account = .signedIn(email: Redacted("anna@example.com"), hasPremium: false, trakt: .linked)
        #expect(AccountFeature.reduce(&state, .signOut) == [.signOut])
    }

    private func signedIn(trakt: TraktLink) -> Account {
        .signedIn(email: Redacted("anna@example.com"), hasPremium: false, trakt: trakt)
    }

    private var unlinked: TraktLink { .unlinked(authorization: Redacted(URL(filePath: "/trakt/auth/user"))) }

    @Test func linkingTraktWaitsForTheLink() {
        var state = AccountFeature.State(account: signedIn(trakt: unlinked))
        let first = AccountFeature.TraktAttempt(number: 1)
        #expect(AccountFeature.reduce(&state, .startTraktLink) == [.awaitTraktLink(first)])
        #expect(state.trakt == .waiting(first))
        #expect(AccountFeature.reduce(&state, .startTraktLink).isEmpty)
        _ = AccountFeature.reduce(&state, .traktLinkFinished(first, .success(())))
        #expect(state.trakt == .idle)
    }

    @Test func linkingTraktNeedsAnUnlinkedAccount() {
        var state = AccountFeature.State()
        #expect(AccountFeature.reduce(&state, .startTraktLink).isEmpty)
        state.account = signedIn(trakt: .linked)
        #expect(AccountFeature.reduce(&state, .startTraktLink).isEmpty)
        #expect(state.trakt == .idle)
    }

    @Test func aLateAnswerToAStoppedTraktLinkIsDropped() {
        var state = AccountFeature.State(account: signedIn(trakt: unlinked))
        _ = AccountFeature.reduce(&state, .startTraktLink)
        #expect(AccountFeature.reduce(&state, .stopTraktLink) == [.stopAwaitingTraktLink])
        #expect(state.trakt == .idle)
        _ = AccountFeature.reduce(&state, .startTraktLink)
        _ = AccountFeature.reduce(&state, .traktLinkFinished(AccountFeature.TraktAttempt(number: 1), .failure(.superseded)))
        #expect(state.trakt == .waiting(AccountFeature.TraktAttempt(number: 2)))
    }

    @Test func aFailedTraktLinkIsShownUntilTriedAgain() {
        var state = AccountFeature.State(account: signedIn(trakt: unlinked))
        _ = AccountFeature.reduce(&state, .startTraktLink)
        _ = AccountFeature.reduce(&state, .traktLinkFinished(AccountFeature.TraktAttempt(number: 1), .failure(.linkExpired)))
        #expect(state.trakt == .failed(.linkExpired))
        #expect(AccountFeature.reduce(&state, .startTraktLink) == [.awaitTraktLink(AccountFeature.TraktAttempt(number: 2))])
    }

    @Test func unlinkingTraktNeedsALink() {
        var state = AccountFeature.State(account: signedIn(trakt: unlinked))
        #expect(AccountFeature.reduce(&state, .unlinkTrakt).isEmpty)
        state.account = signedIn(trakt: .linked)
        #expect(AccountFeature.reduce(&state, .unlinkTrakt) == [.unlinkTrakt])
    }

    @Test func signingOutStopsWaitingForTrakt() {
        var state = AccountFeature.State(account: signedIn(trakt: unlinked))
        _ = AccountFeature.reduce(&state, .startTraktLink)
        #expect(AccountFeature.reduce(&state, .accountChanged(.anonymous)) == [.stopAwaitingTraktLink])
        #expect(state.trakt == .idle)
    }

    @Test func waitingAndStoppingTraktShareAKey() {
        let wait = AccountFeature.key(.awaitTraktLink(AccountFeature.TraktAttempt(number: 1)))
        #expect(wait != nil)
        #expect(wait == AccountFeature.key(.stopAwaitingTraktLink))
        #expect(wait == AccountFeature.key(.awaitTraktLink(AccountFeature.TraktAttempt(number: 2))))
    }

    @Test func emailAndPasswordParseAtTheBoundary() {
        #expect(EmailAddress(" anna@example.com ")?.address.rawValue == "anna@example.com")
        #expect(EmailAddress("anna") == nil)
        #expect(EmailAddress("a@b@c") == nil)
        #expect(Password("") == nil)
        #expect("\(password)" == "<password>")
    }
}
