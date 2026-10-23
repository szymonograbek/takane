import Foundation

extension SmokeTest {
    /// Saves the result, then what Share Logs would send for the last 15 minutes, so a run also shows
    /// what a shared log reveals.
    static func write(_ result: Result) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let url = Self.outputDirectory.appending(path: "smoke-result.json")
        let export = Self.outputDirectory.appending(path: "smoke-export.log")
        do {
            try encoder.encode(result).write(to: url)
            Log.smoke.info("SMOKE result written to \(url.path)")
            try Data(Log.export(.fifteenMinutes, at: .now).utf8).write(to: export)
        } catch {
            Log.smoke.error("SMOKE result write failed: \(error)")
        }
    }
}
