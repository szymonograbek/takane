import Testing

struct AddonsFeatureTests {
    private let addon = InstalledAddon(manifestURL: Fixture.manifest, name: Redacted("Debrid"), version: "1.0.0", isRemovable: true)

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
        #expect(state.install.message == "The add-on's manifest could not be loaded: 404")
        #expect(AddonsFeature.reduce(&state, .install(Fixture.manifest)) == [.install(Fixture.manifest)])
    }

    @Test func openingStartsCleanAfterSuccess() {
        var state = AddonsFeature.State()
        _ = AddonsFeature.reduce(&state, .install(Fixture.manifest))
        _ = AddonsFeature.reduce(&state, .installFinished(Fixture.manifest, .success(addon)))
        #expect(AddonsFeature.reduce(&state, .installOpened).isEmpty)
        #expect(state.install == .idle)
        #expect(state.install.message == nil)
    }

    @Test func openingStartsCleanAfterFailure() {
        var state = AddonsFeature.State()
        _ = AddonsFeature.reduce(&state, .install(Fixture.manifest))
        _ = AddonsFeature.reduce(&state, .installFinished(Fixture.manifest, .failure(.manifestUnavailable(reason: "404"))))
        #expect(AddonsFeature.reduce(&state, .installOpened).isEmpty)
        #expect(state.install == .idle)
    }

    @Test func openingKeepsAnInstallInFlightAndItsOutcome() {
        var state = AddonsFeature.State()
        _ = AddonsFeature.reduce(&state, .install(Fixture.manifest))
        #expect(AddonsFeature.reduce(&state, .installOpened).isEmpty)
        #expect(state.install == .installing(Fixture.manifest))
        _ = AddonsFeature.reduce(&state, .installFinished(Fixture.manifest, .success(addon)))
        #expect(state.install == .installed(addon))
    }
}
