import Foundation
import Testing

struct VideoFingerprintTests {
    private static let chunk = 65_536

    /// A 256 KiB file whose first word is 1, whose last word is 2 and which is zero elsewhere.
    private static let file: Data = {
        var bytes = Data(count: 4 * chunk)
        bytes[0] = 1
        bytes[bytes.count - 8] = 2
        return bytes
    }()

    private static let source = PlaybackSource(url: Redacted(URL(string: "https://debrid.example/movie.mkv").require()), headers: ["X-Token": "secret"])

    /// Answers `Range: bytes=a-b` from `file`, as a server that supports ranges does.
    private static func ranges(_ request: URLRequest) -> HTTPStub.Response {
        let header = request.value(forHTTPHeaderField: "Range") ?? ""
        let bounds = header.dropFirst("bytes=".count).split(separator: "-").compactMap { Int($0) }
        guard bounds.count == 2 else { return HTTPStub.Response(status: 200, body: file) }
        return HTTPStub.Response(
            status: 206,
            body: file.subdata(in: bounds[0]..<(bounds[1] + 1)),
            headers: ["Content-Range": "bytes \(bounds[0])-\(bounds[1])/\(file.count)"]
        )
    }

    @Test func hashesTheSizeWithTheFirstAndLastChunk() async throws {
        let stub = HTTPStub(Self.ranges)

        let fingerprint = try await stub.session.fingerprint(of: Self.source)

        #expect(fingerprint == VideoFingerprint(size: 262_144, hash: "0000000000040003"))
        #expect(stub.requests.map { $0.value(forHTTPHeaderField: "Range") } == ["bytes=0-65535", "bytes=196608-262143"])
        #expect(stub.requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Token") == "secret" })
    }

    @Test func aServerIgnoringRangesFails() async {
        let stub = HTTPStub { _ in HTTPStub.Response(status: 200, body: Self.file) }

        await #expect(throws: HTTPFailure.status(200)) {
            try await stub.session.fingerprint(of: Self.source)
        }
    }
}
