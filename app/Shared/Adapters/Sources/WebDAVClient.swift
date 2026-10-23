import Foundation

/// A WebDAV folder and what signs in to it.
struct WebDAVFolder: Sendable {
    let endpoint: SourceEndpoint
    let username: SourceUsername
    let password: Password

    /// Basic authentication, which goes in the `Authorization` header and never in a URL.
    var authorization: String {
        "Basic \(Data("\(username.name.rawValue):\(password.rawValue)".utf8).base64EncodedString())"
    }

    func url(of path: WebDAVPath) -> URL {
        path.names.reduce(endpoint.url.rawValue) { $0.appending(component: $1) }
    }
}

/// Where a file or folder is under a WebDAV source's folder: its names from the folder down, decoded.
struct WebDAVPath: Hashable, Sendable {
    static let root = WebDAVPath(names: [])

    let names: [String]

    /// The path of `href`, an absolute URL or path as a multi-status answer gives it, under the
    /// folder at `folder`. Nil when it is outside that folder.
    init?(href: String, under folder: WebDAVPath) {
        let names = Self.names(ofPath: href)
        guard names.starts(with: folder.names) else { return nil }
        self.names = Array(names.dropFirst(folder.names.count))
    }

    init(names: [String]) {
        self.names = names
    }

    /// The folder an endpoint's URL points at, from the server's root.
    init(serverPathOf endpoint: SourceEndpoint) {
        names = Self.names(ofPath: endpoint.url.rawValue.path(percentEncoded: true))
    }

    func appending(_ name: String) -> WebDAVPath {
        WebDAVPath(names: names + [name])
    }

    /// Servers differ in which characters they percent-encode, so names compare decoded. A name with
    /// a stray `%` stays as it is.
    private static func names(ofPath text: String) -> [String] {
        var path = Substring(text)
        if let scheme = path.range(of: "://") {
            path = path[scheme.upperBound...].drop { $0 != "/" }
        }
        return path.split(separator: "/").map { $0.removingPercentEncoding ?? String($0) }
    }
}

/// A file or folder that `PROPFIND` lists.
struct WebDAVEntry: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case folder
        case file(size: Int?)
    }

    let path: WebDAVPath
    let kind: Kind
    let modified: Date?
}

/// How much of a share one listing reads, so a huge one cannot hold up the app.
struct WebDAVLimits: Sendable {
    /// Folders below this many levels are not listed.
    var depth = 8
    var entries = 20_000
    /// Each multi-status answer is read up to this size.
    var answerBytes = 32 << 20
}

/// Reaches a WebDAV folder with Basic authentication in a header.
struct WebDAVClient: Sendable {
    let session: URLSession
    var limits = WebDAVLimits()

    /// Checks that the folder answers WebDAV for these credentials: `PROPFIND` with `Depth: 0`,
    /// which a WebDAV server answers with a 207 multi-status.
    func check(_ endpoint: SourceEndpoint, _ username: SourceUsername, _ password: Password) async throws(SourceError) {
        let folder = WebDAVFolder(endpoint: endpoint, username: username, password: password)
        switch try await propfind(.root, depth: "0", in: folder).status {
        case 207: return
        case 401: throw .badCredentials
        default: throw .notWebDAV
        }
    }

    /// Every file and folder under `folder`, within `limits`: one `PROPFIND` with `Depth: infinity`
    /// where the server allows it, as rclone does, else one with `Depth: 1` per folder.
    func list(_ folder: WebDAVFolder) async throws(SourceError) -> [WebDAVEntry] {
        let whole = try await propfind(.root, depth: "infinity", in: folder)
        var listing = Listing(limits: limits)
        switch whole.status {
        case 207:
            _ = try listing.add(whole, from: .root, in: folder)
        case 401:
            throw .badCredentials
        default:
            var folders = [WebDAVPath.root]
            while !folders.isEmpty, !listing.isFull {
                let path = folders.removeFirst()
                let answer = try await propfind(path, depth: "1", in: folder)
                switch answer.status {
                case 207:
                    folders += try listing.add(answer, from: path, in: folder)
                case 401:
                    throw .badCredentials
                default:
                    guard path != .root else { throw .invalidResponse(reason: "PROPFIND answered \(answer.status)") }
                    Log.sources.warning("a folder of \(folder.endpoint) answered \(answer.status), leaving it out")
                }
            }
        }
        if listing.isTruncated {
            Log.sources.warning("listing \(folder.endpoint) stopped at \(listing.entries.count) entries, \(limits.depth) folders deep")
        }
        return listing.entries
    }

    private struct Answer {
        let status: Int
        let body: Data
        /// Whether the body was cut at `WebDAVLimits.answerBytes`.
        let isCut: Bool
    }

    private func propfind(_ path: WebDAVPath, depth: String, in folder: WebDAVFolder) async throws(SourceError) -> Answer {
        var request = URLRequest(url: folder.url(of: path))
        request.httpMethod = "PROPFIND"
        request.setValue(depth, forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(folder.authorization, forHTTPHeaderField: "Authorization")
        request.httpBody = Data(Self.properties.utf8)
        Log.network.debug("→ PROPFIND \(depth) \(folder.endpoint)")
        var body = Data()
        var isCut = false
        let response: URLResponse
        do {
            let (bytes, answer) = try await session.bytes(for: request)
            response = answer
            for try await byte in bytes {
                body.append(byte)
                if body.count >= limits.answerBytes {
                    isCut = true
                    bytes.task.cancel()
                    break
                }
            }
        } catch {
            Log.network.error("✕ PROPFIND \(folder.endpoint): \(error)")
            throw .unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        Log.network.debug("← \(status) PROPFIND \(depth) \(folder.endpoint), \(body.count) bytes")
        return Answer(status: status, body: body, isCut: isCut)
    }

    private static let properties = #"""
        <?xml version="1.0" encoding="utf-8"?><propfind xmlns="DAV:"><prop><resourcetype/><getcontentlength/><getlastmodified/></prop></propfind>
        """#

    /// The entries read so far, within the limits.
    private struct Listing {
        let limits: WebDAVLimits
        var entries: [WebDAVEntry] = []
        var isTruncated = false

        var isFull: Bool { entries.count >= limits.entries }

        /// Adds what `answer` lists below `path`, and returns the folders it lists but not their contents.
        mutating func add(_ answer: Answer, from path: WebDAVPath, in folder: WebDAVFolder) throws(SourceError) -> [WebDAVPath] {
            let parser = MultistatusParser(under: WebDAVPath(serverPathOf: folder.endpoint), limit: limits.entries - entries.count)
            guard parser.parse(answer.body) || answer.isCut || parser.isFull else {
                throw .invalidResponse(reason: "unreadable multi-status")
            }
            isTruncated = isTruncated || answer.isCut || parser.isFull
            let listed = parser.entries.filter { $0.path.names.count > path.names.count && $0.path.names.starts(with: path.names) }
            let deep = listed.filter { $0.path.names.count > limits.depth }
            isTruncated = isTruncated || !deep.isEmpty
            let kept = listed.filter { $0.path.names.count <= limits.depth }
            entries += kept
            return kept.compactMap { entry in
                entry.kind == .folder && entry.path.names.count == path.names.count + 1 && entry.path.names.count < limits.depth ? entry.path : nil
            }
        }
    }
}

/// Reads the responses of a `207 Multi-Status`: each one's href, and from its successful
/// `propstat`s whether it is a folder, its size and when it changed.
private final class MultistatusParser: NSObject, XMLParserDelegate {
    private(set) var entries: [WebDAVEntry] = []
    /// Whether it stopped at its limit.
    private(set) var isFull = false

    private let folder: WebDAVPath
    private let limit: Int
    private let dates: DateFormatter
    private var text = ""
    private var response: Response?
    private var propstat: Properties?

    private struct Response {
        var href: String?
        var found: Properties?
    }

    private struct Properties {
        var isFolder = false
        var size: Int?
        var modified: Date?
        var status: String?

        func merging(_ other: Properties) -> Properties {
            Properties(isFolder: isFolder || other.isFolder, size: size ?? other.size, modified: modified ?? other.modified, status: status)
        }
    }

    init(under folder: WebDAVPath, limit: Int) {
        self.folder = folder
        self.limit = limit
        dates = DateFormatter()
        dates.locale = Locale(identifier: "en_US_POSIX")
        dates.timeZone = TimeZone(identifier: "GMT")
        dates.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    }

    /// False when the body is not well-formed XML, or it stopped at its limit.
    func parse(_ body: Data) -> Bool {
        let parser = XMLParser(data: body)
        parser.shouldProcessNamespaces = true
        parser.delegate = self
        return parser.parse()
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]
    ) {
        guard namespaceURI == "DAV:" else { return }
        text = ""
        switch elementName {
        case "response": response = Response()
        case "propstat": propstat = Properties()
        case "collection": propstat?.isFolder = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        guard namespaceURI == "DAV:" else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "href" where propstat == nil && response?.href == nil:
            response?.href = value
        case "getcontentlength":
            propstat?.size = Int(value)
        case "getlastmodified":
            propstat?.modified = dates.date(from: value)
        case "status":
            propstat?.status = value
        case "propstat":
            // `HTTP/1.1 200 OK`. A 404 propstat names the properties the item lacks.
            let code = propstat?.status?.split(separator: " ").dropFirst().first.flatMap { Int($0) }
            if let code, (200..<300).contains(code), let propstat {
                let found = response?.found
                response?.found = found.map { $0.merging(propstat) } ?? propstat
            }
            propstat = nil
        case "response":
            if let response, let href = response.href, let found = response.found, let path = WebDAVPath(href: href, under: folder) {
                entries.append(WebDAVEntry(path: path, kind: found.isFolder ? .folder : .file(size: found.size), modified: found.modified))
            }
            response = nil
            if entries.count >= limit {
                isFull = true
                parser.abortParsing()
            }
        default:
            break
        }
    }
}
