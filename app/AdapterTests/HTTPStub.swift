import Foundation
import Synchronization

/// A `URLSession` whose requests never leave the process: `respond` answers each one, and every
/// request is recorded. Stubs are independent, so tests using them can run in parallel.
/// A stub stays registered for the life of the test process.
final class HTTPStub: Sendable {
    struct Response: Sendable {
        let status: Int
        let body: Data
        var headers: [String: String] = [:]

        static func json(_ text: String, status: Int = 200) -> Response {
            Response(status: status, body: Data(text.utf8))
        }
    }

    let session: URLSession
    private let id = UUID().uuidString
    private let respond: @Sendable (URLRequest) -> Response
    private let recorded = Mutex<[URLRequest]>([])

    init(_ respond: @escaping @Sendable (URLRequest) -> Response) {
        self.respond = respond
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [StubURLProtocol.stubHeader: id]
        session = URLSession(configuration: configuration)
        StubURLProtocol.stubs.withLock { $0[id] = self }
    }

    var requests: [URLRequest] { recorded.withLock { $0 } }

    fileprivate func answer(_ request: URLRequest) -> Response {
        recorded.withLock { $0.append(request) }
        return respond(request)
    }
}

private final class StubURLProtocol: URLProtocol {
    static let stubHeader = "X-Stub-ID"
    static let stubs = Mutex<[String: HTTPStub]>([:])

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let id = request.value(forHTTPHeaderField: Self.stubHeader),
              let stub = Self.stubs.withLock({ $0[id] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let answer = stub.answer(request)
        guard let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension URLRequest {
    /// The value of one query parameter.
    func query(_ name: String) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == name }?.value
    }
}
