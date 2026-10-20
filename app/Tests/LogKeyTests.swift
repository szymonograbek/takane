import Foundation
import Testing

struct LogKeyTests {
    @Test func readsAsUppercaseGroupsOfFour() {
        #expect(Fixture.releaseKey.text == "A4DQ-OBYH-A4DQ-OBYH-A4DQ-OBYH-A4")
    }

    @Test(arguments: [
        "A4DQ-OBYH-A4DQ-OBYH-A4DQ-OBYH-A4",
        "a4dq-obyh-a4dq-obyh-a4dq-obyh-a4",
        "A4DQOBYHA4DQOBYHA4DQOBYHA4",
        " A4DQ-OBYH-A4DQ OBYH-A4DQ-OBYH-A4 ",
    ])
    func parsesWhatTheUserTypes(text: String) {
        #expect(LogKey(text: text) == Fixture.releaseKey)
    }

    @Test(arguments: ["", "A7DQ", "0000-0000-0000-0000-0000-0000-00"])
    func rejectsTextThatIsNotAKey(text: String) {
        #expect(LogKey(text: text) == nil)
    }

    @Test func legendOpensWithItsKey() throws {
        let legend = ["#abcdef": "Night of the Living Dead", "#ghijkl": "tt0063350"]
        #expect(try Fixture.releaseKey.open(Fixture.releaseKey.seal(legend)) == legend)
    }

    @Test func legendDoesNotOpenWithAnotherKey() {
        let other = LogKey(bytes: Data(repeating: 8, count: LogKey.byteCount)).require()
        #expect(throws: LegendError.wrongKey) { try other.open(Fixture.releaseKey.seal(["#abcdef": "Pioneer One"])) }
        #expect(throws: LegendError.malformed) { try other.open("not a legend") }
    }

    @Test func exportLegendHoldsOnlyTheCodesInTheExport() {
        let files = [
            LogLegend.line("#abcdef", standingFor: "Night of the Living Dead") + LogLegend.line("#ghijkl", standingFor: "Pioneer One"),
            LogLegend.line("#mnopqr", standingFor: "tt0063350"),
        ]
        let text = "push details(movie/#mnopqr)\nStreamsFeature ← lookUp(#abcdef)"
        #expect(LogLegend.entries(in: files, appearingIn: text) == ["#abcdef": "Night of the Living Dead", "#mnopqr": "tt0063350"])
    }
}
