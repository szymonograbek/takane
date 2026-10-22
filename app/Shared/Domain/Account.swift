import Foundation

enum Account: Hashable, Sendable {
    case anonymous
    case signedIn(email: Redacted<String>, hasPremium: Bool, trakt: TraktLink)

    /// Whether the account has an active Stremio Premium subscription.
    var hasPremium: Bool {
        if case .signedIn(_, let hasPremium, _) = self { hasPremium } else { false }
    }

    /// Nil when signed out.
    var trakt: TraktLink? {
        if case .signedIn(_, _, let trakt) = self { trakt } else { nil }
    }
}

/// Whether the account scrobbles what plays here to Trakt.
enum TraktLink: Hashable, Sendable {
    case linked
    /// Never linked, or the authorization expired. Opening `authorization` on another device links it.
    case unlinked(authorization: Redacted<URL>)
}

/// An email address as typed: trimmed, with text on both sides of a single "@".
struct EmailAddress: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let address: Redacted<String>

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }), !trimmed.contains(where: \.isWhitespace) else { return nil }
        address = Redacted(trimmed)
    }

    var description: String { address.description }
    var debugDescription: String { description }
}

/// A non-empty password. Its descriptions are redacted, so it never reaches a log.
struct Password: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let rawValue: String

    init?(_ text: String) {
        guard !text.isEmpty else { return nil }
        rawValue = text
    }

    var description: String { "<password>" }
    var debugDescription: String { description }
}

/// A code the user confirms on another device to sign this one in.
struct LinkCode: Hashable, Sendable {
    let code: Redacted<String>
    /// The page where the code is confirmed. A QR code of it skips typing the code, so it carries the code.
    let link: Redacted<URL>
}

enum AccountError: Error, Equatable, Sendable {
    /// The provider refused the credentials or the code, with its explanation.
    case rejected(message: String)
    /// Nobody confirmed the code, or linked Trakt, in time.
    case linkExpired
    /// Waiting for a code or a Trakt link stopped: a newer one replaced it, or it was cancelled.
    case superseded
    case unavailable(reason: String)
}

/// Signs in and out of the account that syncs add-ons, library and watch progress.
///
/// Add-ons installed while signed out and this device's settings stay after signing in. The
/// library and watch progress are replaced by the account's.
protocol AccountService: Sendable {
    /// The account now, then after every change.
    func account() -> AsyncStream<Account>

    /// A new code for `signIn(confirming:)`, replacing any earlier one.
    func makeLinkCode() async throws(AccountError) -> LinkCode

    /// Waits until someone confirms `code`, then signs in.
    func signIn(confirming code: LinkCode) async throws(AccountError)

    /// Stops waiting for the current code.
    func cancelLinkCode()

    func signIn(email: EmailAddress, password: Password) async throws(AccountError)

    func signOut()

    /// Waits until the account is linked to Trakt, pulling it from the server every few seconds,
    /// then adds the Trakt add-on. Returns at once, adding nothing, when it is linked already.
    /// Throws `.linkExpired` when nobody links it in time and `.superseded` when cancelled.
    func linkTrakt() async throws(AccountError)

    /// Unlinks Trakt from the account and removes the Trakt add-on.
    func unlinkTrakt()

    /// Pulls what changed on the account from other devices (add-ons, library, watch progress) and
    /// pushes what this device has not uploaded yet. Signed out, it does nothing.
    func sync()
}
