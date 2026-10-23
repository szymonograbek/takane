import Foundation
import Testing

struct LogTests {
    @Test func namesTheCaseOfAnEnumWithOrWithoutPayload() {
        #expect(Log.caseName(of: LogSharingFeature.State.idle) == "idle")
        #expect(Log.caseName(of: LogSharingFeature.State.starting(.oneHour)) == "starting")
        #expect(Log.caseName(of: StreamsFeature.State.lookingUp(Fixture.movie, results: nil, offers: nil)) == "lookingUp")
        #expect(Log.caseName(of: AccountFeature.State()) == nil)
    }

    @Test func summaryCutsLongDescriptions() {
        #expect(Log.summary(of: String(repeating: "a", count: 201)) == String(repeating: "a", count: 200) + "…")
        #expect(Log.summary(of: String(repeating: "a", count: 200)) == String(repeating: "a", count: 200))
    }

    @Test func signInSummaryHidesThePassword() {
        let event = AccountFeature.Event.signIn(EmailAddress("anna@example.com").require(), Password("hunter2").require())
        #expect(Log.summary(of: event) == "signIn(anna@example.com, <password>)")
    }
}
