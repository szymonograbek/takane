import Testing

struct SkipSegmentSourceTests {
    @Test func onlyPremiumOffersStremio() {
        #expect(SkipSegmentSource.available(hasPremium: true) == [.stremio, .introDB, .skipDB])
        #expect(SkipSegmentSource.available(hasPremium: false) == [.introDB, .skipDB])
    }

    @Test func nothingStoredDefaultsToStremioWithPremiumAndIntroDBWithout() {
        #expect(SkipSegmentSource.resolved(nil, hasPremium: true) == .stremio)
        #expect(SkipSegmentSource.resolved(nil, hasPremium: false) == .introDB)
    }

    @Test func storedStremioWithoutPremiumReadsAsIntroDB() {
        #expect(SkipSegmentSource.resolved(.stremio, hasPremium: false) == .introDB)
    }

    @Test func anAvailableChoiceIsKept() {
        #expect(SkipSegmentSource.resolved(.skipDB, hasPremium: true) == .skipDB)
        #expect(SkipSegmentSource.resolved(.introDB, hasPremium: true) == .introDB)
        #expect(SkipSegmentSource.resolved(.stremio, hasPremium: true) == .stremio)
        #expect(SkipSegmentSource.resolved(.skipDB, hasPremium: false) == .skipDB)
    }
}
