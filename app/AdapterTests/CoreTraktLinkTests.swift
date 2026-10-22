import Foundation
import Testing

struct CoreTraktLinkTests {
    private static func user(trakt: String) throws -> Profile.User {
        try JSONDecoder().decode(Profile.User.self, from: Data("""
        {"_id": "5f1a2b", "email": "anna@example.com", "premium_expire": null, "trakt": \(trakt)}
        """.utf8))
    }

    @Test func anUnexpiredAuthorizationIsLinked() throws {
        let created = Int(Date.now.timeIntervalSince1970) - 60
        let user = try Self.user(trakt: #"{"created_at": \#(created), "expires_in": 7776000, "access_token": "token"}"#)
        #expect(user.traktLink == .linked)
    }

    @Test func anExpiredOrMissingAuthorizationLinksThroughStremio() throws {
        let authorization = TraktLink.unlinked(authorization: Redacted(URL(string: "https://www.strem.io/trakt/auth/5f1a2b").require()))
        #expect(try Self.user(trakt: #"{"created_at": 1600000000, "expires_in": 7776000, "access_token": "token"}"#).traktLink == authorization)
        #expect(try Self.user(trakt: "null").traktLink == authorization)
    }
}
