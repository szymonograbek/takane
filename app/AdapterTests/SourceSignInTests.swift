import Foundation
import Testing

struct SourceSignInTests {
    private static let id = SourceID("abcd2345").require()
    private static let jellyfinLogin = SourceLogin(
        endpoint: SourceEndpoint("http://jellyfin.local:8096").require(),
        username: SourceUsername("takane").require(),
        password: Password("secret").require()
    )
    private static let davLogin = SourceLogin(
        endpoint: SourceEndpoint("http://nas.local:8197/media").require(),
        username: SourceUsername("takane").require(),
        password: Password("secret").require()
    )

    /// Recorded from the dev server's Jellyfin 12.3 (`GET /System/Info/Public`), its name changed.
    private static let publicInfo = """
    {"LocalAddress":"http://192.168.163.3:8096","ServerName":"Living Room","Version":"12.3.0","ProductName":"Jellyfin Server",\
    "OperatingSystem":"","Id":"a06f9809a64e4ace82e1963731feb8ac","StartupWizardCompleted":true}
    """
    /// The dev server's `POST /Users/AuthenticateByName` answer, cut to the fields the client reads and a fake token.
    private static let authentication = """
    {"User":{"Name":"takane","ServerId":"5b1d1b5a0c7c4c2f9d2a6f3b8e1c0a4d","Id":"8f2c0e4b6a1d4f3e9b7c5a2d1e0f3b6c"},\
    "SessionInfo":{},"AccessToken":"0123456789abcdef0123456789abcdef","ServerId":"5b1d1b5a0c7c4c2f9d2a6f3b8e1c0a4d"}
    """

    private static func jellyfin(_ respond: @escaping @Sendable (URLRequest) -> HTTPStub.Response) -> (JellyfinClient, HTTPStub) {
        let stub = HTTPStub(respond)
        return (JellyfinClient(session: stub.session, version: "1.4.0"), stub)
    }

    private static func jellyfinServer(signIn: HTTPStub.Response) -> @Sendable (URLRequest) -> HTTPStub.Response {
        { request in request.url?.path() == "/System/Info/Public" ? .json(publicInfo) : signIn }
    }

    @Test func jellyfinTradesThePasswordForAToken() async throws {
        let (client, stub) = Self.jellyfin(Self.jellyfinServer(signIn: .json(Self.authentication)))

        let (name, session) = try await client.signIn(Self.jellyfinLogin, for: Self.id)

        #expect(name == "Living Room")
        #expect(session == JellyfinSession(userID: "8f2c0e4b6a1d4f3e9b7c5a2d1e0f3b6c", token: "0123456789abcdef0123456789abcdef"))
        let request = try #require(stub.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "http://jellyfin.local:8096/Users/AuthenticateByName")
        #expect(request.value(forHTTPHeaderField: "Authorization")
            == #"MediaBrowser Client="Takane", Device="Mac", DeviceId="takane-abcd2345", Version="1.4.0""#)
        let body = try #require(request.body)
        #expect(try JSONDecoder().decode([String: String].self, from: body) == ["Username": "takane", "Pw": "secret"])
        #expect(!String(describing: session).contains("0123456789abcdef"))
    }

    @Test func jellyfinRefusingThePasswordIsBadCredentials() async {
        let (client, _) = Self.jellyfin(Self.jellyfinServer(signIn: .json("Error processing request.", status: 401)))
        await #expect(throws: SourceError.badCredentials) { try await client.signIn(Self.jellyfinLogin, for: Self.id) }
    }

    @Test func aServerWithoutJellyfinsPublicInfoIsNotJellyfin() async {
        let (missing, _) = Self.jellyfin { _ in .json("Not Found", status: 404) }
        await #expect(throws: SourceError.notJellyfin) { try await missing.signIn(Self.jellyfinLogin, for: Self.id) }
        let (locked, _) = Self.jellyfin { _ in .json("", status: 401) }
        await #expect(throws: SourceError.notJellyfin) { try await locked.signIn(Self.jellyfinLogin, for: Self.id) }
        let (other, _) = Self.jellyfin { _ in .json(#"{"status":"ok"}"#) }
        await #expect(throws: SourceError.notJellyfin) { try await other.signIn(Self.jellyfinLogin, for: Self.id) }
    }

    @Test func aKeptJellyfinSessionChecksItsUser() async throws {
        let session = JellyfinSession(userID: "8f2c", token: "kept-token")
        let (client, stub) = Self.jellyfin(Self.jellyfinServer(signIn: .json(#"{"Id":"8f2c","Name":"Takane"}"#)))

        let name = try await client.check(session, at: Self.jellyfinLogin.endpoint, as: Self.jellyfinLogin.username, for: Self.id)

        #expect(name == "Living Room")
        let request = try #require(stub.requests.last)
        #expect(request.url?.path() == "/Users/Me")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasSuffix(#", Token="kept-token""#) == true)
        let otherUser = SourceUsername("guest").require()
        await #expect(throws: SourceError.badCredentials) {
            try await client.check(session, at: Self.jellyfinLogin.endpoint, as: otherUser, for: Self.id)
        }
        let (expired, _) = Self.jellyfin(Self.jellyfinServer(signIn: .json("", status: 401)))
        await #expect(throws: SourceError.badCredentials) {
            try await expired.check(session, at: Self.jellyfinLogin.endpoint, as: Self.jellyfinLogin.username, for: Self.id)
        }
    }

    @Test func webDAVAsksForTheFolderItselfWithBasicAuthentication() async throws {
        let stub = HTTPStub { _ in HTTPStub.Response(status: 207, body: Data("<d:multistatus xmlns:d=\"DAV:\"/>".utf8)) }

        try await WebDAVClient(session: stub.session).check(Self.davLogin.endpoint, Self.davLogin.username, Self.davLogin.password)

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "PROPFIND")
        #expect(request.url?.absoluteString == "http://nas.local:8197/media")
        #expect(request.value(forHTTPHeaderField: "Depth") == "0")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic dGFrYW5lOnNlY3JldA==")
    }

    @Test func webDAVMapsRefusalsAndOtherServers() async {
        let refused = WebDAVClient(session: HTTPStub { _ in .json("", status: 401) }.session)
        await #expect(throws: SourceError.badCredentials) {
            try await refused.check(Self.davLogin.endpoint, Self.davLogin.username, Self.davLogin.password)
        }
        let page = WebDAVClient(session: HTTPStub { _ in .json("<html></html>") }.session)
        await #expect(throws: SourceError.notWebDAV) {
            try await page.check(Self.davLogin.endpoint, Self.davLogin.username, Self.davLogin.password)
        }
        let notAllowed = WebDAVClient(session: HTTPStub { _ in .json("", status: 405) }.session)
        await #expect(throws: SourceError.notWebDAV) {
            try await notAllowed.check(Self.davLogin.endpoint, Self.davLogin.username, Self.davLogin.password)
        }
    }
}

/// Against the dev servers of `scripts/dev-sources.sh up`, at the URLs `scripts/dev-sources.sh env`
/// prints (prefixed with `TEST_RUNNER_` to reach the test process), localhost by default.
struct SourceSignInLiveTests {
    private static let environment = ProcessInfo.processInfo.environment
    private static let jellyfinURL = SourceEndpoint(environment["DEV_JELLYFIN_URL"] ?? "http://localhost:8196").require()
    private static let webDAVURL = SourceEndpoint(environment["DEV_WEBDAV_URL"] ?? "http://localhost:8197").require()
    private static let user = SourceUsername(environment["DEV_SOURCES_USER"] ?? "takane").require()
    private static let password = Password(environment["DEV_SOURCES_PASSWORD"] ?? "takane-dev").require()
    private static let wrongPassword = Password("not-the-password").require()
    private static let id = SourceID("livetest").require()
    private static let jellyfin = JellyfinClient(session: .shared, version: "live-test")
    private static let webDAV = WebDAVClient(session: .shared)

    @Test(.enabled(if: LiveTests.enabled, "set STREMIO_LIVE_TESTS=1 and run scripts/dev-sources.sh up"))
    func jellyfinSignsInAndKeepsItsSession() async throws {
        let login = SourceLogin(endpoint: Self.jellyfinURL, username: Self.user, password: Self.password)
        let (name, session) = try await Self.jellyfin.signIn(login, for: Self.id)
        #expect(!name.isEmpty)
        #expect(!session.token.isEmpty)
        #expect(try await Self.jellyfin.check(session, at: Self.jellyfinURL, as: Self.user, for: Self.id) == name)
    }

    @Test(.enabled(if: LiveTests.enabled, "set STREMIO_LIVE_TESTS=1 and run scripts/dev-sources.sh up"))
    func jellyfinRefusesAWrongPassword() async {
        await #expect(throws: SourceError.badCredentials) {
            try await Self.jellyfin.signIn(SourceLogin(endpoint: Self.jellyfinURL, username: Self.user, password: Self.wrongPassword), for: Self.id)
        }
    }

    @Test(.enabled(if: LiveTests.enabled, "set STREMIO_LIVE_TESTS=1 and run scripts/dev-sources.sh up"))
    func aWebDAVFolderIsNotJellyfin() async {
        await #expect(throws: SourceError.notJellyfin) {
            try await Self.jellyfin.signIn(SourceLogin(endpoint: Self.webDAVURL, username: Self.user, password: Self.password), for: Self.id)
        }
    }

    @Test(.enabled(if: LiveTests.enabled, "set STREMIO_LIVE_TESTS=1 and run scripts/dev-sources.sh up"))
    func webDAVSignsInAndRefusesAWrongPassword() async throws {
        try await Self.webDAV.check(Self.webDAVURL, Self.user, Self.password)
        await #expect(throws: SourceError.badCredentials) { try await Self.webDAV.check(Self.webDAVURL, Self.user, Self.wrongPassword) }
    }

    @Test(.enabled(if: LiveTests.enabled, "set STREMIO_LIVE_TESTS=1 and run scripts/dev-sources.sh up"))
    func aJellyfinServerIsNotWebDAV() async {
        await #expect(throws: SourceError.notWebDAV) { try await Self.webDAV.check(Self.jellyfinURL, Self.user, Self.password) }
    }
}
