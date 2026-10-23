import Foundation

/// A title a source names without an IMDb id, as Cinemeta's search is asked for it.
struct TitleQuery: Hashable, Sendable {
    let kind: SourceTitle.Kind
    let name: String
    let year: Int?

    /// The same for names that differ only in case, accents, spacing or punctuation.
    var key: String {
        "\(kind.name):\(Self.comparable(name)):\(year.map(String.init) ?? "")"
    }

    /// `Amélie`, `amelie` and `A-melie` read the same; so do `A.I.` and `AI`.
    static func comparable(_ name: String) -> String {
        String(name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased().filter { $0.isLetter || $0.isNumber })
    }
}

extension TitleQuery {
    /// Nil for a title whose name is nothing to search for.
    init?(_ title: SourceTitle) {
        guard !Self.comparable(title.name.rawValue).isEmpty else { return nil }
        self.init(kind: title.kind, name: title.name.rawValue, year: title.year)
    }
}

/// Finds the IMDb ids of titles a source names without one, on Cinemeta's search. It takes an id
/// only when exactly one result has the title's name and, when the name gives one, its year, so a
/// title is never guessed. Answers, found or not, are kept on this device, so relaunching and
/// reading a source again ask nothing more. A title not found is asked again after `retryAfter`,
/// in case Cinemeta has it by then; a failed request is asked again on the next read.
actor TitleMatcher {
    private static let endpoint = "https://v3-cinemeta.strem.io/catalog"
    private static let defaultsKey = "sources.titleMatches"
    /// Kept answers, at most. The oldest go first.
    private static let capacity = 2000
    /// Lookups at once, so a large library does not flood Cinemeta.
    private static let width = 4

    private struct Answer: Codable {
        /// Nil when no single title fits.
        let id: String?
        let asked: Date
    }

    private let session: URLSession
    private let defaults: UserDefaults
    private let retryAfter: Duration
    private var answers: [String: Answer]
    /// The lookups under way, by query key, each the batch that asks it.
    private var lookups: [String: Task<Void, Never>] = [:]

    init(session: URLSession, defaults: UserDefaults, retryAfter: Duration = .seconds(7 * 24 * 3600)) {
        self.session = session
        self.defaults = defaults
        self.retryAfter = retryAfter
        answers = defaults.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode([String: Answer].self, from: $0) } ?? [:]
    }

    /// The ids found for `queries` within `budget`. Lookups still running then go on, and a later
    /// call finds what they found.
    func ids(for queries: Set<TitleQuery>, within budget: Duration) async -> [TitleQuery: MediaID] {
        let unknown = queries.filter { answer(for: $0) == nil && lookups[$0.key] == nil }
        if !unknown.isEmpty {
            let batch = Task { await self.look(up: Array(unknown)) }
            for query in unknown { lookups[query.key] = batch }
        }
        let running = Set(queries.compactMap { lookups[$0.key] })
        if !running.isEmpty {
            // Waiting on a task's value ignores cancellation, so the budget ends the wait instead.
            let (done, end) = AsyncStream<Never>.makeStream()
            Task { for task in running { await task.value }; end.finish() }
            let timer = Task { try? await Task.sleep(for: budget); end.finish() }
            for await _ in done {}
            timer.cancel()
        }
        return queries.reduce(into: [:]) { found, query in
            if let id = answer(for: query)?.id.flatMap(MediaID.init) { found[query] = id }
        }
    }

    private func answer(for query: TitleQuery) -> Answer? {
        guard let answer = answers[query.key] else { return nil }
        guard answer.id != nil || Date.now.timeIntervalSince(answer.asked) < retryAfter / .seconds(1) else { return nil }
        return answer
    }

    private func look(up queries: [TitleQuery]) async {
        await withTaskGroup(of: (TitleQuery, Lookup).self) { group in
            var waiting = queries[...]
            for query in waiting.prefix(Self.width) { group.addTask { [session] in (query, await Self.search(query, on: session)) } }
            waiting = waiting.dropFirst(Self.width)
            for await (query, lookup) in group {
                switch lookup {
                case .found(let id):
                    answers[query.key] = Answer(id: id.rawValue, asked: .now)
                    Log.sources.info("\(Redacted(query.name)) is \(id) on Cinemeta")
                case .notFound:
                    answers[query.key] = Answer(id: nil, asked: .now)
                    Log.sources.info("\(Redacted(query.name)) is no single title on Cinemeta")
                case .failed:
                    break
                }
                lookups[query.key] = nil
                if let next = waiting.popFirst() { group.addTask { [session] in (next, await Self.search(next, on: session)) } }
            }
        }
        if answers.count > Self.capacity {
            for (key, _) in answers.sorted(by: { $0.value.asked < $1.value.asked }).prefix(answers.count - Self.capacity) { answers[key] = nil }
        }
        if let data = try? JSONEncoder().encode(answers) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    private enum Lookup {
        case found(MediaID)
        /// No title fits, or several do.
        case notFound
        /// Cinemeta could not be asked, so the next read asks again.
        case failed
    }

    private static func search(_ query: TitleQuery, on session: URLSession) async -> Lookup {
        guard let text = query.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: "\(endpoint)/\(query.kind.name)/top/search=\(text).json")
        else { return .failed }
        do {
            let found = try await session.json(CinemetaSearch.self, for: URLRequest(url: url), decoder: JSONDecoder())
            return found.only(query).map(Lookup.found) ?? .notFound
        } catch {
            Log.sources.warning("searching Cinemeta for \(Redacted(query.name)) failed: \(error)")
            return .failed
        }
    }
}

/// Cinemeta's answer to a catalog search, only what tells titles apart.
private struct CinemetaSearch: Decodable {
    struct Meta: Decodable {
        let id: String
        let name: String
        /// `2010` for a film, `2010-2011` or `2010-` for a show.
        let releaseInfo: String?

        var year: Int? { releaseInfo?.firstMatch(of: /\d{4}/).flatMap { Int($0.output) } }
    }

    let metas: [Meta]

    /// The only result with `query`'s name and year, or with its name when it has no year.
    func only(_ query: TitleQuery) -> MediaID? {
        let name = TitleQuery.comparable(query.name)
        let fitting = Set(metas.filter { meta in
            meta.id.hasPrefix("tt") && TitleQuery.comparable(meta.name) == name && (query.year.map { $0 == meta.year } ?? true)
        }.map(\.id))
        guard fitting.count == 1 else { return nil }
        return fitting.first.flatMap(MediaID.init)
    }
}
