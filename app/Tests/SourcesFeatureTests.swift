import Testing

struct SourcesFeatureTests {
    private let jellyfin = SourceLogin(
        endpoint: SourceEndpoint("http://jellyfin.local:8096").require(),
        username: SourceUsername("takane").require(),
        password: Password("secret").require()
    )
    private let webDAV = SourceLogin(
        endpoint: SourceEndpoint("https://dav.example/media").require(),
        username: SourceUsername("takane").require(),
        password: Password("secret").require()
    )
    private let source = MediaSource(
        id: SourceID("ab23cd45").require(), kind: .jellyfin, name: SourceName("Living Room").require(),
        endpoint: SourceEndpoint("http://jellyfin.local:8096").require(), username: SourceUsername("takane").require()
    )
    private let other = MediaSource(
        id: SourceID("zz77yy66").require(), kind: .webDAV, name: SourceName("media").require(),
        endpoint: SourceEndpoint("https://dav.example/media").require(), username: SourceUsername("takane").require()
    )

    private func edit(_ source: MediaSource, _ password: PasswordChange, name: String? = nil) -> SourceEdit {
        SourceEdit(
            name: name.flatMap(SourceName.init) ?? source.name, endpoint: source.endpoint, username: source.username, password: password
        )
    }

    @Test func listsTheSourcesItIsGiven() {
        var state = SourcesFeature.State()
        #expect(SourcesFeature.reduce(&state, .sourcesChanged([source, other])).isEmpty)
        #expect(state.sources == [source, other])
    }

    @Test func savesOneSourceAtATime() {
        var state = SourcesFeature.State(sources: [source])
        #expect(SourcesFeature.reduce(&state, .add(.jellyfin, jellyfin)) == [.add(.jellyfin, jellyfin)])
        #expect(SourcesFeature.reduce(&state, .add(.webDAV, webDAV)).isEmpty)
        #expect(SourcesFeature.reduce(&state, .update(source.id, edit(source, .keep))).isEmpty)
        #expect(state.save == .saving(.new(.jellyfin, jellyfin.endpoint)))
    }

    @Test func reportsTheSavedSource() {
        var state = SourcesFeature.State()
        _ = SourcesFeature.reduce(&state, .add(.jellyfin, jellyfin))
        _ = SourcesFeature.reduce(&state, .saveFinished(.new(.jellyfin, jellyfin.endpoint), .success(source)))
        #expect(state.save == .saved(source))
    }

    @Test func dropsAnswersForAnotherSave() {
        var state = SourcesFeature.State(sources: [source])
        _ = SourcesFeature.reduce(&state, .update(source.id, edit(source, .keep)))
        _ = SourcesFeature.reduce(&state, .saveFinished(.new(.jellyfin, jellyfin.endpoint), .failure(.badCredentials)))
        _ = SourcesFeature.reduce(&state, .saveFinished(.existing(other.id), .success(other)))
        #expect(state.save == .saving(.existing(source.id)))
    }

    @Test func aFailedSaveCanBeRetried() {
        var state = SourcesFeature.State()
        _ = SourcesFeature.reduce(&state, .add(.webDAV, webDAV))
        _ = SourcesFeature.reduce(&state, .saveFinished(.new(.webDAV, webDAV.endpoint), .failure(.notWebDAV)))
        #expect(state.save == .failed(.new(.webDAV, webDAV.endpoint), .notWebDAV))
        #expect(SourcesFeature.reduce(&state, .add(.webDAV, webDAV)) == [.add(.webDAV, webDAV)])
    }

    @Test func updatesOnlyAListedSource() {
        var state = SourcesFeature.State(sources: [source])
        let password = PasswordChange.replace(Password("new").require())
        #expect(SourcesFeature.reduce(&state, .update(other.id, edit(other, password))).isEmpty)
        #expect(state.save == .idle)
        #expect(
            SourcesFeature.reduce(&state, .update(source.id, edit(source, password)))
                == [.update(source.id, edit(source, password))]
        )
        _ = SourcesFeature.reduce(&state, .saveFinished(.existing(source.id), .failure(.badCredentials)))
        #expect(state.save == .failed(.existing(source.id), .badCredentials))
    }

    @Test func renamesASource() {
        var state = SourcesFeature.State(sources: [source])
        let rename = edit(source, .keep, name: "Home Server")
        #expect(SourcesFeature.reduce(&state, .update(source.id, rename)) == [.update(source.id, rename)])
        let renamed = MediaSource(id: source.id, kind: source.kind, name: rename.name, endpoint: source.endpoint, username: source.username)
        _ = SourcesFeature.reduce(&state, .saveFinished(.existing(source.id), .success(renamed)))
        #expect(state.save == .saved(renamed))
    }

    @Test func aRenameWaitsForTheSaveInFlight() {
        var state = SourcesFeature.State(sources: [source])
        _ = SourcesFeature.reduce(&state, .add(.webDAV, webDAV))
        #expect(SourcesFeature.reduce(&state, .update(source.id, edit(source, .keep, name: "Home Server"))).isEmpty)
        #expect(state.save == .saving(.new(.webDAV, webDAV.endpoint)))
    }

    @Test func openingTheFormStartsCleanAfterASave() {
        var state = SourcesFeature.State()
        _ = SourcesFeature.reduce(&state, .add(.jellyfin, jellyfin))
        _ = SourcesFeature.reduce(&state, .saveFinished(.new(.jellyfin, jellyfin.endpoint), .failure(.unreachable)))
        _ = SourcesFeature.reduce(&state, .formOpened)
        #expect(state.save == .idle)
    }

    @Test func openingTheFormKeepsASaveInFlight() {
        var state = SourcesFeature.State()
        _ = SourcesFeature.reduce(&state, .add(.jellyfin, jellyfin))
        _ = SourcesFeature.reduce(&state, .formOpened)
        #expect(state.save == .saving(.new(.jellyfin, jellyfin.endpoint)))
        _ = SourcesFeature.reduce(&state, .saveFinished(.new(.jellyfin, jellyfin.endpoint), .success(source)))
        #expect(state.save == .saved(source))
    }

    @Test func removesOneSourceAtATime() {
        var state = SourcesFeature.State(sources: [source, other])
        #expect(SourcesFeature.reduce(&state, .remove(source.id)) == [.remove(source.id)])
        #expect(SourcesFeature.reduce(&state, .remove(other.id)).isEmpty)
        _ = SourcesFeature.reduce(&state, .removeFinished(other.id, .success(())))
        #expect(state.removal == .removing(source.id))
        _ = SourcesFeature.reduce(&state, .removeFinished(source.id, .success(())))
        #expect(state.removal == .idle)
    }

    @Test func removingASourceThatIsGoneDoesNothing() {
        var state = SourcesFeature.State(sources: [other])
        #expect(SourcesFeature.reduce(&state, .remove(source.id)).isEmpty)
        #expect(state.removal == .idle)
    }

    @Test func aFailedRemovalCanBeRetried() {
        var state = SourcesFeature.State(sources: [source])
        _ = SourcesFeature.reduce(&state, .remove(source.id))
        _ = SourcesFeature.reduce(&state, .removeFinished(source.id, .failure(.storageFailed(reason: "locked"))))
        #expect(state.removal == .failed(source.id, .storageFailed(reason: "locked")))
        #expect(SourcesFeature.reduce(&state, .remove(source.id)) == [.remove(source.id)])
    }

    @Test func savingAndRemovingRunSideBySide() {
        var state = SourcesFeature.State(sources: [source])
        _ = SourcesFeature.reduce(&state, .add(.webDAV, webDAV))
        #expect(SourcesFeature.reduce(&state, .remove(source.id)) == [.remove(source.id)])
        #expect(state.save == .saving(.new(.webDAV, webDAV.endpoint)))
    }
}

struct SourceValueTests {
    @Test func endpointsAreHTTPWithAHostAndNoCredential() {
        #expect(SourceEndpoint(" http://192.168.1.5:8096 ")?.url.rawValue.absoluteString == "http://192.168.1.5:8096")
        #expect(SourceEndpoint("https://dav.example/media/")?.url.rawValue.path() == "/media/")
        #expect(SourceEndpoint("ftp://dav.example") == nil)
        #expect(SourceEndpoint("192.168.1.5:8096") == nil)
        #expect(SourceEndpoint("http://") == nil)
        #expect(SourceEndpoint("http://user:pass@dav.example") == nil)
        #expect(SourceEndpoint("http://user@dav.example") == nil)
        #expect(SourceEndpoint("http://jellyfin.local/?api_key=abc") == nil)
    }

    @Test func sourceIDsAreEightLowercaseBase32Characters() {
        #expect(SourceID("ab12cd34") == nil)
        #expect(SourceID("abcd2345")?.rawValue == "abcd2345")
        #expect(SourceID("ABCD2345") == nil)
        #expect(SourceID("abc-2345") == nil)
        #expect(SourceID("abcd23456") == nil)
        let made = SourceID.random()
        #expect(SourceID(made.rawValue) == made)
    }

    @Test func namesAreTrimmedAndNotEmpty() {
        #expect(SourceName("  Home Server ")?.text.rawValue == "Home Server")
        #expect(SourceName(" ") == nil)
        #expect(SourceName(hostOf: SourceEndpoint("http://nas.local:8096/media").require()).text.rawValue == "nas.local")
    }

    @Test func usernamesAreTrimmedAndNotEmpty() {
        #expect(SourceUsername("  takane ")?.name.rawValue == "takane")
        #expect(SourceUsername("  ") == nil)
    }
}
