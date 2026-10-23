import Foundation
import Testing

struct RedactedTests {
    @Test func releaseGivesEqualValuesOneCodeAndOthersAnother() {
        #expect(Fixture.inRelease { "\(Redacted("Night of the Living Dead"))" } == "#ik5eu7")
        #expect(Fixture.inRelease { "\(Redacted("Night of the Living Dead"))" } == "#ik5eu7")
        #expect(Fixture.inRelease { "\(Redacted("Pioneer One"))" } == "#atfkli")
    }

    @Test func releaseCodesAnAddonLinkWhole() {
        let manifest = ManifestURL("https://torrentio.strem.fun/realdebrid=k7fmQ2/manifest.json").require()
        #expect(manifest.url.text(in: Fixture.release) == "#z5ztru")
        #expect(manifest.url.text(in: .revealed) == "https://torrentio.strem.fun/realdebrid=k7fmQ2/manifest.json")
    }

    @Test func releaseCodesATitleAndKeepsAnEpisodesNumbers() {
        let movie = PlayableID("tt0063350").require()
        #expect(Fixture.inRelease { "\(movie) \(movie.media)" } == "#q5r4qa #q5r4qa")
        #expect(Fixture.inRelease { "\(PlayableID("tt0944947:1:4").require())" } == "#f46ip7 S1E4")
        #expect(Fixture.inRelease { "\(PlayableID("kitsu:1376:4").require())" } == "#d5dvgj")
        #expect(Fixture.inRelease { "\(Fixture.channel)" } == "#aydmqw")
        #expect("\(PlayableID("tt0944947:1:4").require())" == "tt0944947:1:4")
    }

    @Test func releaseLookUpNamesNoTitle() {
        let event = StreamsFeature.Event.lookUp(PlayableID("tt0063350").require(), account: .anonymous)
        #expect(Fixture.inRelease { Log.summary(of: event) } == "lookUp(#q5r4qa, account: StremioTVTests.Account.anonymous)")
    }

    @Test func releaseSearchNamesNoQuery() {
        let event = SearchFeature.Event.queryChanged(SearchText("night of the living dead"))
        #expect(Fixture.inRelease { Log.summary(of: event) } == "queryChanged(Optional(#v4pvno))")
    }

    @Test func releaseRoutePushNamesNoTitle() {
        let route = Route.details(Fixture.preview("tt0063350"))
        #expect(Fixture.inRelease { "push \(route)" } == "push details(movie/#q5r4qa)")
    }

    @Test func releaseOpenedStreamNamesNoTitleFileOrAddon() {
        let candidate = StreamCandidate(
            id: StreamCandidate.ID(addon: ManifestURL("https://torrentio.strem.fun/realdebrid=ABC/manifest.json").require(), index: 0),
            item: PlayableID("tt0063350").require(),
            name: Redacted("Torrentio\n4k"),
            description: Redacted("Night.of.the.Living.Dead.1968.2160p.mkv ⚙️ ThePirateBay"),
            filename: Redacted("Night.of.the.Living.Dead.1968.2160p.mkv"),
            playability: .unsupported(kind: "torrent"),
            tracking: TrackingToken(payload: Redacted(.null))
        )
        let event = PlayerFeature.Event.open(candidate, title: Redacted("Night of the Living Dead"))
        #expect(Fixture.inRelease { Log.summary(of: event) } == """
        open(StremioTVTests.StreamCandidate(id: StremioTVTests.StreamCandidate.ID(addon: #mff22y, index: 0), \
        item: #q5r4qa, name: Optional(#uzi56b), description: Optional(#2wr7ez), filename: Optional(#yjqakm)…
        """)
    }

    /// Tests build in Debug, which reveals values wherever they are interpolated, nested ones included.
    @Test func debugBuildsRevealValuesInLogText() {
        #expect("\(Fixture.manifest)" == "https://addon.example/manifest.json")
        let account = Account.signedIn(email: Redacted("anna@example.com"), hasPremium: false, trakt: .linked)
        #expect("\(account)" == "signedIn(email: anna@example.com, hasPremium: false, trakt: StremioTVTests.TraktLink.linked)")
        #expect("\(LinkCode(code: Redacted("K7Q2"), link: Redacted(URL(filePath: "/link"))))" == "LinkCode(code: K7Q2, link: file:///link)")
    }
}
