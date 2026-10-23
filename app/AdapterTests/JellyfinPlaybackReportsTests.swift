import Foundation
import Testing

struct JellyfinPlaybackReportsTests {
    private static let start = ContinuousClock.now
    private static let sintel = "9952106a602633409354098d0e941df4"
    private static let beachDay = "0ae549595ae7368e7ee4c03bfe70839c"

    private static func video(_ item: String) -> InProcessURL {
        InProcessURL(URL(string: "https://abcd2345.source.invalid/play/\(item)/\(item)").require()).require()
    }

    /// Plays `events`, each at its offset from the start, and returns what was reported.
    private static func reports(_ events: [(Duration, InProcessPlayback)]) -> [JellyfinPlaybackReport] {
        var reports = JellyfinPlaybackReports()
        return events.flatMap { offset, event in reports.reports(after: event, at: start + offset) }
    }

    private static func summary(_ reports: [JellyfinPlaybackReport]) -> [String] {
        reports.map { "\($0.kind) \($0.item.rawValue.prefix(4)) \($0.position) paused=\($0.isPaused)" }
    }

    @Test func aPlaybackStartsAtItsFirstPositionReportsEveryTenSecondsAndStopsWhereItWas() {
        let reports = Self.reports([
            (.zero, .began(Self.video(Self.sintel))),
            (.seconds(1), .position(.seconds(30))),
            (.seconds(5), .position(.seconds(34))),
            (.seconds(11), .position(.seconds(40))),
            (.seconds(12), .paused(true)),
            (.seconds(13), .paused(true)),
            (.seconds(20), .paused(false)),
            (.seconds(21), .position(.seconds(41))),
            (.seconds(22), .stopped),
            (.seconds(23), .stopped),
        ])

        #expect(Self.summary(reports) == [
            "started 9952 30.0 seconds paused=false",
            "progress 9952 40.0 seconds paused=false",
            "progress 9952 40.0 seconds paused=true",
            "progress 9952 40.0 seconds paused=false",
            "stopped 9952 41.0 seconds paused=false",
        ])
        #expect(Set(reports.map(\.playSession)).count == 1)
        #expect(reports.allSatisfy { $0.source.rawValue == "abcd2345" })
    }

    @Test func anotherStreamStopsTheOneBefore() {
        let reports = Self.reports([
            (.zero, .began(Self.video(Self.sintel))),
            (.seconds(1), .position(.seconds(1))),
            (.seconds(2), .began(Self.video(Self.beachDay))),
            (.seconds(3), .position(.zero)),
            (.seconds(4), .stopped),
        ])

        #expect(Self.summary(reports) == [
            "started 9952 1.0 seconds paused=false",
            "stopped 9952 1.0 seconds paused=false",
            "started 0ae5 0.0 seconds paused=false",
            "stopped 0ae5 0.0 seconds paused=false",
        ])
        #expect(reports[0].playSession != reports[2].playSession)
    }

    @Test func nothingIsReportedForAStreamThatNeverPlayedOrIsNotASources() {
        let subtitle = InProcessURL(URL(string: "https://abcd2345.source.invalid/subtitle/\(Self.sintel)/\(Self.sintel)/0").require()).require()

        let unplayed = Self.reports([(.zero, .began(Self.video(Self.sintel))), (.seconds(1), .paused(true)), (.seconds(2), .stopped)])
        let elsewhere = Self.reports([(.zero, .stopped), (.seconds(1), .position(.seconds(5))), (.seconds(2), .paused(true))])
        let notAVideo = Self.reports([(.zero, .began(subtitle)), (.seconds(1), .position(.seconds(5)))])

        #expect(unplayed.isEmpty && elsewhere.isEmpty && notAVideo.isEmpty)
    }
}
