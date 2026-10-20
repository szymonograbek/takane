import Foundation

/// Free text in which personal values sit among other words: core's and Rust's lines, core's JSON,
/// AetherEngine's lines. `Redacted` codes a value the app holds; this holds every rule for finding
/// such values inside text, and codes each by `Redaction.current`, so a value reads the same code
/// whichever way it reaches a line. Under `.revealed` text stays as it is.
///
/// Every rule is here so one file says what a release log can hold. It lives in Domain because it
/// needs only Foundation and the domain's ids, and adapters reach it as they reach `Redacted`.
enum RedactedMask {
    /// `text` with every web address, title id and long token coded. `Log` runs it on every line.
    static func line(_ text: String) -> String {
        let redaction = Redaction.current
        guard case .pseudonymized = redaction else { return text }
        return text
            .replacing(webAddress) { redaction.text(String($0.output)) }
            .replacing(titleID) { redaction.text(String($0.output)) }
            .replacing(longToken) { redaction.text(String($0.output)) }
    }

    /// core's JSON (dispatched actions, events): every string is coded except core's own words under
    /// `vocabulary`; keys, numbers and booleans stay, so a dispatch still reads as what it does. A
    /// video id keeps its season and episode: `#k3f9qa:1:4`.
    static func json(_ value: JSONValue) -> JSONValue {
        guard case .pseudonymized(let pseudonymizer) = Redaction.current else { return value }
        return coded(value, under: nil, by: pseudonymizer)
    }

    /// An AetherEngine line. Besides what `line` codes, the engine names the origins it fetched from
    /// as `host:port` and `host=…`, the files it opened, and subtitle tracks by their title, which can
    /// be a release name. The engine's own files (`seg0.mp4`, `master.m3u8`) stay.
    static func engineLine(_ text: String) -> String {
        let redaction = Redaction.current
        guard case .pseudonymized = redaction else { return text }
        var text = line(text).replacing(hostAndPort) { redaction.text(String($0.output)) }
        for field in [hostField, renditionName, optionName] {
            text = text.replacing(field) { "\($0.output.1)\(redaction.text(String($0.output.2)))\($0.output.3)" }
        }
        return text.replacing(fileName) { match in
            let name = String(match.output)
            return name.wholeMatch(of: engineFile) == nil ? redaction.text(name) : name
        }
    }

    /// What a code's legend may reveal of `value`: titles, add-ons and the account, never what grants
    /// access. A web address keeps only its origin, since add-on and stream links carry debrid keys,
    /// and long tokens, such as an auth key, go.
    static func legendText(of value: String) -> String {
        value
            .replacing(webAddress) { match in
                let url = URL(string: String(match.output).replacing("\\/", with: "/"))
                return url.flatMap { url in url.host().map { "\(url.scheme ?? "https")://\($0)/…" } } ?? "…"
            }
            .replacing(longToken, with: "…")
    }

    private static let vocabulary: Set<String> = [
        "action", "model", "field", "event", "type", "resource", "libItemType", "posterShape",
        "device", "deviceType", "code", "message",
    ]

    private static func coded(_ value: JSONValue, under key: String?, by pseudonymizer: Pseudonymizer) -> JSONValue {
        switch value {
        case .object(let fields):
            .object(fields.reduce(into: [:]) { result, field in
                result[field.key] = coded(field.value, under: field.key, by: pseudonymizer)
            })
        case .array(let values):
            .array(values.map { coded($0, under: key, by: pseudonymizer) })
        case .string where key.map(vocabulary.contains) == true:
            value
        case .string(let text):
            if let video = PlayableID(text), let (season, episode) = video.episodeNumbers {
                .string("\(pseudonymizer.code(video.media.rawValue)):\(season):\(episode)")
            } else {
                .string(pseudonymizer.code(text))
            }
        case .null, .bool, .number:
            value
        }
    }

    // Regexes are immutable once built but not declared Sendable.
    // A web address, whole: even a host says which add-ons and debrid services the user chose.
    // swiftlint:disable:next nonisolated_unsafe
    nonisolated(unsafe) private static let webAddress = #/https?:(?:\\?/){2}[^\s"'<>),]+/#
    // IMDb's ids (`tt0063350`, also inside `tt0944947:1:1`) and the `provider:number` ones of anime
    // and TV databases.
    // swiftlint:disable:next nonisolated_unsafe
    nonisolated(unsafe) private static let titleID = /\btt\d{5,}\b|\b(?:kitsu|mal|anilist|anidb|tmdb|tvdb|imdb):\d+\b/
    // Debrid API keys, playback ids: 32 or more URL-safe characters.
    // swiftlint:disable:next nonisolated_unsafe
    nonisolated(unsafe) private static let longToken = /[A-Za-z0-9_\-]{32,}/
    // swiftlint:disable:next nonisolated_unsafe
    nonisolated(unsafe) private static let hostAndPort = /\b(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}:\d+\b/
    // These capture what comes before the value, the value, and what comes after it.
    // swiftlint:disable:next nonisolated_unsafe
    nonisolated(unsafe) private static let hostField = /(host=)([^\s,)]+)()/
    // swiftlint:disable:next nonisolated_unsafe
    nonisolated(unsafe) private static let renditionName = /(rendition ")([^"]*)(")/
    // swiftlint:disable:next nonisolated_unsafe
    nonisolated(unsafe) private static let optionName = /( opt=)(.*?)( groupOpts=)/
    // swiftlint:disable:next nonisolated_unsafe
    nonisolated(unsafe) private static let fileName = /[^\s\/"'=]+\.(?:mkv|mp4|m4v|avi|mov|webm|ts|m2ts|srt|vtt|ass|ssa|sub|zip|gz)\b/
    // swiftlint:disable:next nonisolated_unsafe
    nonisolated(unsafe) private static let engineFile = /(?:seg\d+|init|media|master)\.mp4/
}
