import Foundation
import Testing

struct LogKeyTests {
    @Test func readsAsUppercaseGroupsOfFour() {
        #expect(Fixture.releaseKey.text == "K0FM-Q2XD-91NB")
    }

    @Test(arguments: [
        "K0FM-Q2XD-91NB",
        "k0fm-q2xd-91nb",
        "K0FMQ2XD91NB",
        " K0FM Q2XD-91NB ",
        "KOFM-Q2XD-9INB",
        "kofm-q2xd-9lnb",
    ])
    func parsesWhatTheUserTypes(text: String) {
        #expect(LogKey(text: text) == Fixture.releaseKey)
    }

    @Test(arguments: ["", "K0FM-Q2XD-91N", "K0FM-Q2XD-91NB2", "K0FM-Q2XD-91NU", "A4DQ-OBYH-A4DQ-OBYH-A4DQ-OBYH-A4"])
    func rejectsTextThatIsNotAKey(text: String) {
        #expect(LogKey(text: text) == nil)
    }

    @Test func randomKeysParseBackFromTheirText() {
        let key = LogKey.random()
        #expect(LogKey(text: key.text) == key)
        #expect(key.text.count == 14)
    }

    @Test func codesDependOnTheKey() {
        let other = LogSecrets(LogKey(text: "K0FM-Q2XD-91NC").require())
        #expect(Fixture.releaseSecrets.pseudonymizer.code("tt0063350") == "#q5r4qa")
        #expect(other.pseudonymizer.code("tt0063350") == "#qc25xy")
    }

    @Test func legendOpensWithItsKey() throws {
        let legend = ["#abcdef": "Night of the Living Dead", "#ghijkl": "tt0063350"]
        #expect(try Fixture.releaseSecrets.open(Fixture.releaseSecrets.seal(legend)) == legend)
    }

    @Test func legendDoesNotOpenWithAnotherKey() {
        let other = LogSecrets(LogKey(text: "K0FM-Q2XD-91NC").require())
        #expect(throws: LegendError.wrongKey) { try other.open(Fixture.releaseSecrets.seal(["#abcdef": "Pioneer One"])) }
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
