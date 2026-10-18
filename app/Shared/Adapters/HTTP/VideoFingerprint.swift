import Foundation

/// What OpenSubtitles, and the subtitle add-ons built on it, match a video file by.
struct VideoFingerprint: Equatable, Sendable {
    let size: UInt64
    /// OpenSubtitles' hash: the size plus every little-endian 64-bit word of the first and last
    /// 64 KiB, as 16 hex digits.
    let hash: String
}

extension URLSession {
    private static let hashChunk: UInt64 = 65_536

    /// Fingerprints `source` from two range requests, without downloading the rest of the file.
    func fingerprint(of source: PlaybackSource) async throws(HTTPFailure) -> VideoFingerprint {
        let (head, size) = try await bytes(0..<Self.hashChunk, of: source)
        guard size >= Self.hashChunk else { throw .decoding("file of \(size) B is smaller than one hash chunk") }
        let (tail, _) = try await bytes((size - Self.hashChunk)..<size, of: source)
        var hash = size
        for chunk in [head, tail] {
            chunk.withUnsafeBytes { raw in
                for offset in stride(from: 0, to: raw.count, by: 8) {
                    hash &+= UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
                }
            }
        }
        return VideoFingerprint(size: size, hash: String(format: "%016llx", hash))
    }

    /// The bytes in `range` and the file's total size, from a `206` response's `Content-Range`.
    /// Any other response is a failure, read no further: a server ignoring `Range` sends the whole file.
    private func bytes(_ range: Range<UInt64>, of source: PlaybackSource) async throws(HTTPFailure) -> (Data, size: UInt64) {
        var request = URLRequest(url: source.url)
        for (name, value) in source.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        let url = source.url.absoluteString
        Log.network.debug("→ GET \(url) bytes \(range)")
        let stream: AsyncBytes
        let response: URLResponse
        do {
            (stream, response) = try await self.bytes(for: request)
        } catch {
            Log.network.error("✕ \(url): \(error)")
            throw .transport(error.localizedDescription)
        }
        let http = response as? HTTPURLResponse
        guard http?.statusCode == 206 else {
            stream.task.cancel()
            Log.network.warning("← \(http?.statusCode ?? 0) for a range of \(url)")
            throw .status(http?.statusCode ?? 0)
        }
        // `Content-Range: bytes 0-65535/1234567890`
        let contentRange = http?.value(forHTTPHeaderField: "Content-Range")
        guard let size = contentRange?.split(separator: "/").last.flatMap({ UInt64($0) }) else {
            stream.task.cancel()
            throw .decoding("Content-Range \(contentRange ?? "missing")")
        }
        var data = Data(capacity: range.count)
        do {
            for try await byte in stream.prefix(range.count) {
                data.append(byte)
            }
        } catch {
            Log.network.error("✕ \(url): \(error)")
            throw .transport(error.localizedDescription)
        }
        guard data.count == range.count else { throw .decoding("\(data.count) of \(range.count) B") }
        Log.network.debug("← 206 \(data.count)B of \(size)B \(url)")
        return (data, size)
    }
}
