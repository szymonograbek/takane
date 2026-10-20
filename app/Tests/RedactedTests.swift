import Foundation
import Testing

struct RedactedTests {
    @Test func releaseGivesEqualValuesOneCodeAndOthersAnother() {
        #expect(Fixture.inRelease { "\(Redacted("Night of the Living Dead"))" } == "#eql2ul")
        #expect(Fixture.inRelease { "\(Redacted("Night of the Living Dead"))" } == "#eql2ul")
        #expect(Fixture.inRelease { "\(Redacted("Pioneer One"))" } == "#kpysry")
    }

    @Test func releaseCodesAnAddonLinkWhole() {
        let manifest = ManifestURL("https://torrentio.strem.fun/realdebrid=k7fmQ2/manifest.json").require()
        #expect(manifest.url.text(in: Fixture.release) == "#kt25an")
        #expect(manifest.url.text(in: .revealed) == "https://torrentio.strem.fun/realdebrid=k7fmQ2/manifest.json")
    }

    @Test func releaseCodesATitleAndKeepsAnEpisodesNumbers() {
        let movie = PlayableID("tt0063350").require()
        #expect(Fixture.inRelease { "\(movie) \(movie.media)" } == "#u6bvt2 #u6bvt2")
        #expect(Fixture.inRelease { "\(PlayableID("tt0944947:1:4").require())" } == "#cmsgfs S1E4")
        #expect(Fixture.inRelease { "\(PlayableID("kitsu:1376:4").require())" } == "#2bb2zo")
        #expect(Fixture.inRelease { "\(Fixture.channel)" } == "#msxvod")
        #expect("\(PlayableID("tt0944947:1:4").require())" == "tt0944947:1:4")
    }

    @Test func releaseLookUpNamesNoTitle() {
        #expect(Fixture.inRelease { Log.summary(of: StreamsFeature.Event.lookUp(PlayableID("tt0063350").require())) } == "lookUp(#u6bvt2)")
    }

    @Test func releaseSearchNamesNoQuery() {
        let event = SearchFeature.Event.queryChanged(SearchText("night of the living dead"))
        #expect(Fixture.inRelease { Log.summary(of: event) } == "queryChanged(Optional(#ctmmqy))")
    }

    @Test func releaseRoutePushNamesNoTitle() {
        let route = Route.details(Fixture.preview("tt0063350"))
        #expect(Fixture.inRelease { "push \(route)" } == "push details(movie/#u6bvt2)")
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
        open(StremioTVTests.StreamCandidate(id: StremioTVTests.StreamCandidate.ID(addon: #7vfqcl, index: 0), \
        item: #u6bvt2, name: Optional(#mz6ypk), description: Optional(#xfxq2h), filename: Optional(#xwkcx4)…
        """)
    }

    /// Tests build in Debug, which reveals values wherever they are interpolated, nested ones included.
    @Test func debugBuildsRevealValuesInLogText() {
        #expect("\(Fixture.manifest)" == "https://addon.example/manifest.json")
        #expect("\(Account.signedIn(email: Redacted("anna@example.com")))" == "signedIn(email: anna@example.com)")
        #expect("\(LinkCode(code: Redacted("K7Q2"), link: Redacted(URL(filePath: "/link"))))" == "LinkCode(code: K7Q2, link: file:///link)")
    }
}
