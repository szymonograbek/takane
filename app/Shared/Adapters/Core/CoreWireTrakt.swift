import Foundation

extension Profile {
    /// core's `TraktInfo`, without the access token. Nil on a user that never linked Trakt or unlinked it.
    struct Trakt: Decodable, Sendable {
        /// Unix seconds.
        let createdAt: TimeInterval
        /// Seconds after `createdAt`.
        let expiresIn: TimeInterval

        private enum CodingKeys: String, CodingKey {
            case createdAt = "created_at"
            case expiresIn = "expires_in"
        }
    }
}

extension Profile.User {
    /// Redirects to Trakt's authorization, which Stremio's site stores on the account the path names.
    private static let traktAuthorization: URL = {
        guard let url = URL(string: "https://www.strem.io/trakt/auth") else { preconditionFailure("a valid literal URL") }
        return url
    }()

    /// Core's own check: linked until the authorization expires.
    var traktLink: TraktLink {
        if let trakt, Date(timeIntervalSince1970: trakt.createdAt + trakt.expiresIn) > .now { return .linked }
        return .unlinked(authorization: Redacted(Self.traktAuthorization.appending(path: id.rawValue)))
    }
}
