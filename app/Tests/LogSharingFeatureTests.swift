import Foundation
import Testing

struct LogSharingFeatureTests {
    private let link = LogLink(url: Redacted(URL(string: "http://192.168.1.20:8080/k7fm").require()))

    private func sharing(_ window: LogWindow = .oneHour) -> LogSharingFeature.State {
        var state = LogSharingFeature.State.idle
        _ = LogSharingFeature.reduce(&state, .appeared)
        _ = LogSharingFeature.reduce(&state, .select(window))
        _ = LogSharingFeature.reduce(&state, .shareFinished(window, .success(link)))
        return state
    }

    @Test func appearingSharesTheLastHour() {
        var state = LogSharingFeature.State.idle
        #expect(LogSharingFeature.reduce(&state, .appeared) == [.share(.oneHour)])
        #expect(state == .starting(.oneHour))
        _ = LogSharingFeature.reduce(&state, .shareFinished(.oneHour, .success(link)))
        #expect(state == .sharing(link, .oneHour))
    }

    @Test func choosingAnotherWindowKeepsShowingTheLink() {
        var state = sharing()
        #expect(LogSharingFeature.reduce(&state, .select(.sevenDays)) == [.share(.sevenDays)])
        #expect(state == .sharing(link, .sevenDays))
    }

    @Test func dropsAnswersForAnEarlierWindow() {
        var state = LogSharingFeature.State.idle
        _ = LogSharingFeature.reduce(&state, .appeared)
        _ = LogSharingFeature.reduce(&state, .select(.sixHours))
        _ = LogSharingFeature.reduce(&state, .shareFinished(.oneHour, .failure(.noLocalNetwork)))
        #expect(state == .starting(.sixHours))
        _ = LogSharingFeature.reduce(&state, .shareFinished(.sixHours, .success(link)))
        #expect(state == .sharing(link, .sixHours))
    }

    @Test func aFailureCanBeRetried() {
        var state = LogSharingFeature.State.idle
        _ = LogSharingFeature.reduce(&state, .appeared)
        _ = LogSharingFeature.reduce(&state, .shareFinished(.oneHour, .failure(.noLocalNetwork)))
        #expect(state == .failed(.oneHour, .noLocalNetwork))
        #expect(LogSharingFeature.reduce(&state, .retry) == [.share(.oneHour)])
        #expect(state == .starting(.oneHour))
    }

    @Test func leavingStopsSharingAndIgnoresLateAnswers() {
        var state = sharing(.fifteenMinutes)
        #expect(LogSharingFeature.reduce(&state, .disappeared) == [.stop])
        #expect(state == .idle)
        _ = LogSharingFeature.reduce(&state, .shareFinished(.fifteenMinutes, .success(link)))
        #expect(state == .idle)
        #expect(LogSharingFeature.reduce(&state, .disappeared).isEmpty)
    }
}
