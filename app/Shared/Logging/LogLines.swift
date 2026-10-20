import Foundation

/// The lines of a log file. Each starts with the time it was written; a message of several lines
/// continues on lines without one. Lines are in the order they were written.
enum LogLines {
    /// Local time with its offset, to the millisecond, such as `2026-10-20T17:30:12.345+0200`.
    private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

    static func timestamp(_ date: Date) -> String {
        date.formatted(timestampStyle)
    }

    /// The part of `text` written at or after `start`: from its first line stamped then or later to the end.
    static func written(since start: Date, in text: String) -> Substring {
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            if let written = date(of: text[lineStart..<lineEnd]), written >= start {
                return text[lineStart...]
            }
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
        }
        return ""
    }

    /// When `line` was written, or nil for a line that continues the one before.
    private static func date(of line: Substring) -> Date? {
        try? Date(String(line.prefix { $0 != " " }), strategy: timestampStyle)
    }
}

/// The values release logs' codes stand for. Each session's legend file holds one JSON object per
/// line, one code to its value. An export ends with the legend of the codes in it, sealed with the
/// install's `LogKey` under `marker`; `scripts/reveal-log.swift` reads that format.
enum LogLegend {
    static let marker = "--- legend (encrypted) ---"

    static func line(_ code: String, standingFor value: String) -> String {
        let json = (try? JSONEncoder().encode([code: value])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return json + "\n"
    }

    /// The entries of `files`, legend files' text, whose codes appear in `text`.
    static func entries(in files: [String], appearingIn text: String) -> [String: String] {
        let codes = Set(text.matches(of: /#[a-z2-7]{6}/).map { String($0.output) })
        var legend: [String: String] = [:]
        for line in files.flatMap({ $0.split(separator: "\n") }) {
            guard let entry = try? JSONDecoder().decode([String: String].self, from: Data(line.utf8)) else { continue }
            legend.merge(entry.filter { codes.contains($0.key) }) { first, _ in first }
        }
        return legend
    }

    /// The end of an export.
    static func section(_ sealed: String) -> String {
        "\n\(marker)\n\(sealed)\n"
    }
}
