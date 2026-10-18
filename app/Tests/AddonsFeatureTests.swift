import Testing

struct AddonsFeatureTests {
    private let addon = InstalledAddon(manifestURL: Fixture.manifest, name: "Debrid", version: "1.0.0")

    @Test func installsOneManifestAtATime() {
        var state = AddonsFeature.State()
        #expect(AddonsFeature.reduce(&state, .install(Fixture.manifest)) == [.install(Fixture.manifest)])
        #expect(AddonsFeature.reduce(&state, .install(Fixture.otherManifest)).isEmpty)
        #expect(state.install == .installing(Fixture.manifest))
        #expect(state.install.message == "Installing…")
    }

    @Test func reportsTheOutcomeOfThePendingInstall() {
        var state = AddonsFeature.State()
        _ = AddonsFeature.reduce(&state, .install(Fixture.manifest))
        _ = AddonsFeature.reduce(&state, .installFinished(Fixture.manifest, .success(addon)))
        #expect(state.install.message == "Installed Debrid")
    }

    @Test func ignoresOutcomesForOtherManifests() {
        var state = AddonsFeature.State()
        _ = AddonsFeature.reduce(&state, .install(Fixture.manifest))
        _ = AddonsFeature.reduce(&state, .installFinished(Fixture.otherManifest, .failure(.timedOut(stage: "manifest"))))
        #expect(state.install == .installing(Fixture.manifest))
    }

    @Test func failureCanBeRetried() {
        var state = AddonsFeature.State()
        _ = AddonsFeature.reduce(&state, .install(Fixture.manifest))
        _ = AddonsFeature.reduce(&state, .installFinished(Fixture.manifest, .failure(.manifestUnavailable(reason: "404"))))
        #expect(state.install.message == "manifest failed: 404")
        #expect(AddonsFeature.reduce(&state, .install(Fixture.manifest)) == [.install(Fixture.manifest)])
    }
}
