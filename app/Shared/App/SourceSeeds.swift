#if DEBUG
import Foundation

/// Sources a debug launch adds through `MediaSourceService.add`, so a verification run needs no
/// typing: `STREMIO_SOURCES` (see `LaunchOptions`) holds a JSON array of
/// `{"kind": "jellyfin" or "webdav", "url": …, "username": …, "password": …}`. A source already
/// stored with the same kind, URL and user is skipped, so relaunching with the option adds none twice.
/// Debug builds only, since the option holds passwords.
struct SourceSeeds {
    private struct Seed: Decodable {
        let kind: String
        let url: String
        let username: String
        let password: String
    }

    private let logins: [(SourceKind, SourceLogin)]

    init?(options: [String: String]) {
        guard let text = options["STREMIO_SOURCES"] else { return nil }
        guard let seeds = try? JSONDecoder().decode([Seed].self, from: Data(text.utf8)) else {
            Log.sources.error("STREMIO_SOURCES is not a JSON array of sources")
            return nil
        }
        logins = seeds.enumerated().compactMap { index, seed in
            let kind: SourceKind? = switch seed.kind {
            case "jellyfin": .jellyfin
            case "webdav": .webDAV
            default: nil
            }
            guard let kind, let endpoint = SourceEndpoint(seed.url), let username = SourceUsername(seed.username),
                  let password = Password(seed.password)
            else {
                Log.sources.error("STREMIO_SOURCES entry \(index) is not a source")
                return nil
            }
            return (kind, SourceLogin(endpoint: endpoint, username: username, password: password))
        }
    }

    func add(to service: any MediaSourceService) async {
        var current = service.sources().makeAsyncIterator()
        let stored = await current.next() ?? []
        for (kind, login) in logins {
            if stored.contains(where: { $0.kind == kind && $0.endpoint == login.endpoint && $0.username == login.username }) {
                Log.sources.info("\(kind) source at \(login.endpoint) already stored")
                continue
            }
            do {
                let source = try await service.add(kind, login)
                Log.sources.info("seeded \(kind) source \(source.id) named \(source.name)")
            } catch {
                Log.sources.error("seeding the \(kind) source at \(login.endpoint) failed: \(error)")
            }
        }
    }
}
#endif
