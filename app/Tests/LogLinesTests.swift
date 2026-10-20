import Foundation
import Testing

struct LogLinesTests {
    private let text = """
    2026-10-20T17:29:59.999+0200 DEBUG [app] (main) before the window
    went on
    2026-10-20T17:30:00.000+0200 INFO  [core] (bg) at its start
    which went on
    2026-10-20T15:45:00.000Z ERROR [player] (main) later, written in another time zone

    """

    private func date(_ text: String) -> Date {
        (try? Date(text, strategy: .iso8601)).require()
    }

    @Test func keepsLinesFromTheWindowsStartWithTheLinesThatContinueThem() {
        #expect(LogLines.written(since: date("2026-10-20T15:30:00Z"), in: text) == """
        2026-10-20T17:30:00.000+0200 INFO  [core] (bg) at its start
        which went on
        2026-10-20T15:45:00.000Z ERROR [player] (main) later, written in another time zone

        """)
    }

    @Test func keepsNothingWrittenBeforeTheWindow() {
        #expect(LogLines.written(since: date("2026-10-20T16:00:00Z"), in: text).isEmpty)
    }

    @Test func readsTheTimeItWrites() {
        let written = date("2026-10-20T15:30:00Z")
        let line = "\(LogLines.timestamp(written)) INFO  [app] (main) launch\n"
        #expect(LogLines.written(since: written, in: line) == line)
        #expect(LogLines.written(since: written.addingTimeInterval(0.001), in: line).isEmpty)
    }
}
