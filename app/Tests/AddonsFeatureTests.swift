import Testing

struct AddonsFeatureTests {
    private let addon = InstalledAddon(
        manifestURL: Fixture.manifest, name: Redacted("Debrid"), version: "1.0.0", isRemovable: true, isEnabled: true
    )
    private let official = InstalledAddon(
        manifestURL: Fixture.otherManifest, name: Redacted("Cinemeta"), version: "3.0.0", isRemovable: false, isEnabled: true
    )

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

    @Test func switchesAnAddonOffAndBackOn() {
        var state = AddonsFeature.State(installed: [addon])
        #expect(AddonsFeature.reduce(&state, .setEnabled(Fixture.manifest, false)) == [.setEnabled(Fixture.manifest, false)])
        #expect(state.change == .switching(Fixture.manifest, isEnabled: false))
        _ = AddonsFeature.reduce(&state, .setEnabledFinished(Fixture.manifest, false, .success(())))
        #expect(state.change == .idle)

        state.installed = [addon.switched(on: false)]
        #expect(AddonsFeature.reduce(&state, .setEnabled(Fixture.manifest, true)) == [.setEnabled(Fixture.manifest, true)])
        #expect(state.change == .switching(Fixture.manifest, isEnabled: true))
    }

    @Test func switchesOffAddonsThatCannotBeRemoved() {
        var state = AddonsFeature.State(installed: [official])
        #expect(AddonsFeature.reduce(&state, .setEnabled(Fixture.otherManifest, false)) == [.setEnabled(Fixture.otherManifest, false)])
    }

    @Test func switchesOnlyInstalledAddonsToAnotherValue() {
        var state = AddonsFeature.State(installed: [addon])
        #expect(AddonsFeature.reduce(&state, .setEnabled(Fixture.manifest, true)).isEmpty)
        #expect(AddonsFeature.reduce(&state, .setEnabled(Fixture.otherManifest, false)).isEmpty)
        #expect(state.change == .idle)
    }

    @Test func runsOneChangeAtATime() {
        var state = AddonsFeature.State(installed: [addon, official])
        _ = AddonsFeature.reduce(&state, .setEnabled(Fixture.manifest, false))
        #expect(AddonsFeature.reduce(&state, .setEnabled(Fixture.otherManifest, false)).isEmpty)
        #expect(AddonsFeature.reduce(&state, .uninstall(Fixture.manifest)).isEmpty)
        #expect(state.change == .switching(Fixture.manifest, isEnabled: false))

        _ = AddonsFeature.reduce(&state, .setEnabledFinished(Fixture.manifest, false, .success(())))
        _ = AddonsFeature.reduce(&state, .uninstall(Fixture.manifest))
        #expect(AddonsFeature.reduce(&state, .setEnabled(Fixture.otherManifest, false)).isEmpty)
        #expect(state.change == .removing(Fixture.manifest))
    }

    @Test func dropsAnswersToAnotherSwitch() {
        var state = AddonsFeature.State(installed: [addon])
        _ = AddonsFeature.reduce(&state, .setEnabled(Fixture.manifest, false))
        _ = AddonsFeature.reduce(&state, .setEnabledFinished(Fixture.manifest, true, .failure(.timedOut(stage: "add-on switch"))))
        _ = AddonsFeature.reduce(&state, .setEnabledFinished(Fixture.otherManifest, false, .failure(.timedOut(stage: "add-on switch"))))
        _ = AddonsFeature.reduce(&state, .uninstallFinished(Fixture.manifest, .failure(.timedOut(stage: "add-on removal"))))
        #expect(state.change == .switching(Fixture.manifest, isEnabled: false))
    }

    @Test func aFailedSwitchShowsAndCanBeRetried() {
        var state = AddonsFeature.State(installed: [addon])
        _ = AddonsFeature.reduce(&state, .setEnabled(Fixture.manifest, false))
        _ = AddonsFeature.reduce(&state, .setEnabledFinished(Fixture.manifest, false, .failure(.timedOut(stage: "add-on switch"))))
        #expect(state.change == .failed(Fixture.manifest, .timedOut(stage: "add-on switch")))
        #expect(AddonsFeature.reduce(&state, .setEnabled(Fixture.manifest, false)) == [.setEnabled(Fixture.manifest, false)])
    }
}

private extension InstalledAddon {
    func switched(on isEnabled: Bool) -> InstalledAddon {
        InstalledAddon(manifestURL: manifestURL, name: name, version: version, isRemovable: isRemovable, isEnabled: isEnabled)
    }
}
