import Foundation
import Testing

struct CoreDeviceSettingsTests {
    private let defaults = UserDefaults(suiteName: "CoreDeviceSettingsTests.\(UUID().uuidString)").require()

    private static func profile(premiumExpire: String?) throws -> Profile {
        let expiry = premiumExpire.map { "\"\($0)\"" } ?? "null"
        return try JSONDecoder().decode(Profile.self, from: Data("""
        {"auth": {"user": {"_id": "u1", "email": "anna@example.com", "premium_expire": \(expiry)}}, "addons": [], "settings": {}}
        """.utf8))
    }

    private let premium: Profile
    private let expired: Profile
    private let free: Profile

    init() throws {
        premium = try Self.profile(premiumExpire: "2099-01-01T00:00:00Z")
        expired = try Self.profile(premiumExpire: "2020-01-01T00:00:00.123Z")
        free = try Self.profile(premiumExpire: nil)
    }

    @Test func readsPremiumFromTheProfile() {
        #expect(premium.hasPremium)
        #expect(!expired.hasPremium)
        #expect(!free.hasPremium)
    }

    @Test func nothingStoredReadsAsStremioWithPremiumAndIntroDBWithout() {
        var preferences = Fixture.preferences(skipSegmentSource: .skipDB)

        CoreDeviceSettings.read(into: &preferences, from: defaults, for: premium)
        #expect(preferences == Fixture.preferences(skipSegmentSource: .stremio))

        CoreDeviceSettings.read(into: &preferences, from: defaults, for: expired)
        #expect(preferences == Fixture.preferences(skipSegmentSource: .introDB))
    }

    @Test(arguments: SkipSegmentSource.allCases)
    func readsWhatItWrites(source: SkipSegmentSource) {
        CoreDeviceSettings.write(Fixture.preferences(skipSegmentSource: source), into: defaults, for: premium)
        var preferences = Fixture.preferences(seekStep: .thirty)

        CoreDeviceSettings.read(into: &preferences, from: defaults, for: premium)

        #expect(preferences == Fixture.preferences(seekStep: .thirty, skipSegmentSource: source))
    }

    @Test func storedStremioWithoutPremiumReadsAsIntroDB() {
        CoreDeviceSettings.write(Fixture.preferences(skipSegmentSource: .stremio), into: defaults, for: free)
        var preferences = Fixture.preferences()

        CoreDeviceSettings.read(into: &preferences, from: defaults, for: free)

        #expect(preferences.skipSegmentSource == .introDB)
    }

    @Test func storedSkipDBStaysWithPremium() {
        CoreDeviceSettings.write(Fixture.preferences(skipSegmentSource: .skipDB), into: defaults, for: free)
        var preferences = Fixture.preferences()

        CoreDeviceSettings.read(into: &preferences, from: defaults, for: premium)

        #expect(preferences.skipSegmentSource == .skipDB)
    }

    @Test func savingTheDefaultLetsItFollowTheAccount() {
        CoreDeviceSettings.write(Fixture.preferences(skipSegmentSource: .introDB), into: defaults, for: free)
        var preferences = Fixture.preferences()

        CoreDeviceSettings.read(into: &preferences, from: defaults, for: premium)

        #expect(preferences.skipSegmentSource == .stremio)
    }

    @Test func readsAnUnknownValueAsTheDefault() {
        defaults.set("tvdb", forKey: "skipSegmentSource")
        var preferences = Fixture.preferences(skipSegmentSource: .skipDB)

        CoreDeviceSettings.read(into: &preferences, from: defaults, for: free)

        #expect(preferences.skipSegmentSource == .introDB)
    }
}
