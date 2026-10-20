import Foundation
import Testing

struct RedactedMaskTests {
    @Test(arguments: [
        ("fetch failed url=https://x/KEY/stream/movie/tt1.json Could not connect", "fetch failed url=#27tlt6 Could not connect"),
        (#"{"transportUrl":"https:\/\/torrentio.strem.fun\/realdebrid=ABC123\/manifest.json"}"#, ##"{"transportUrl":"#jrr2mt"}"##),
        (
            "load 'https://a.example/p?t=1', then (https://v3-cinemeta.strem.io/manifest.json) and <http://127.0.0.1:11470/x>",
            "load '#c7tdxz', then (#weuute) and <#vu6yxi>"
        ),
        (
            "[OriginBudget] https://comet.elfhosted.com:- is served through https://aiostreams.elfhosted.com:-",
            "[OriginBudget] #mamw5h is served through #qupuka"
        ),
        ("#4 ← 200 512B in 0.2 seconds #27tlt6", "#4 ← 200 512B in 0.2 seconds #27tlt6"),
    ])
    func releaseCodesEveryAddressWhole(line: String, coded: String) {
        #expect(Fixture.inRelease { RedactedMask.line(line) } == coded)
    }

    @Test func releaseGivesARepeatedAddressOneCode() {
        let line = "GET https://a.example/x, again https://a.example/x, then https://b.example/y"
        #expect(Fixture.inRelease { RedactedMask.line(line) } == "GET #khesyd, again #khesyd, then #kw27bk")
    }

    @Test func releaseCodesTitleIdsAndKeepsEpisodeNumbers() {
        let line = "watching tt0063350, then tt0063350:1:4 and kitsu:1376:4"
        #expect(Fixture.inRelease { RedactedMask.line(line) } == "watching #u6bvt2, then #u6bvt2:1:4 and #zb7gca:4")
    }

    @Test func releaseCodesLongTokensOutsideAddresses() {
        let line = "authKey 0123456789abcdefghijABCDEFGHIJ_-xyz in https://h/KEY/stream/movie/tt1.json"
        #expect(Fixture.inRelease { RedactedMask.line(line) } == "authKey #ypropp in #4g4uwg")
    }

    @Test func debugLeavesLinesAsTheyAre() {
        let line = "load https://a.example/x for tt0063350"
        #expect(RedactedMask.line(line) == line)
    }

    @Test(arguments: [
        ("[OriginBudget] comet.elfhosted.com:443 via host=nexus-288.weur.tb-cdn.st", "[OriginBudget] #nhfjkx via host=#tk27yu"),
        ("[HTTPDiscIOReader] Night.of.the.Living.Dead.1968.mkv: adopted a prewarmed source", "[HTTPDiscIOReader] #nyu57t: adopted a prewarmed source"),
        (
            #"[AetherEngine] #316: selected injected rendition "OpenSubtitles AMIABLE" for external id=7"#,
            ##"[AetherEngine] #316: selected injected rendition "#63eaee" for external id=7"##
        ),
        ("[AetherEngine] native subtitle select: item=3 opt=English SDH groupOpts=2", "[AetherEngine] native subtitle select: item=3 opt=#h7a6k6 groupOpts=2"),
        ("[HLSLocalServer] GET /seg0.mp4 and init.mp4 for master.m3u8", "[HLSLocalServer] GET /seg0.mp4 and init.mp4 for master.m3u8"),
    ])
    func releaseCodesWhatAnEngineLineNames(line: String, coded: String) {
        #expect(Fixture.inRelease { RedactedMask.engineLine(line) } == coded)
    }

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    @Test func releaseKeepsAnActionsVocabularyAndCodesWhatItIsAbout() throws {
        let dispatch = try json("""
        {"action":{"action":"Load","args":{"args":{"stream":{"behaviorHints":{"filename":"Night.of.the.Living.Dead.1968.mkv",\
        "videoSize":10564835435},"name":"Torrentio"},"streamRequest":{"path":{"id":"tt0063350:1:4","resource":"stream",\
        "type":"series"}}},"model":"Player"}},"field":"player"}
        """)
        #expect(Fixture.inRelease { RedactedMask.json(dispatch).compactDescription } == """
        {"action":{"action":"Load","args":{"args":{"stream":{"behaviorHints":{"filename":"#nyu57t","videoSize":10564835435},\
        "name":"#s6qfyh"},"streamRequest":{"path":{"id":"#u6bvt2:1:4","resource":"stream","type":"series"}}},"model":"Player"}},\
        "field":"player"}
        """)
    }

    @Test func releaseCodesTheTitleAnEventNamesAndItsSearches() throws {
        let event = try json("""
        {"context":{"libItemID":"tt0063350","libItemName":"Night of the Living Dead","libItemType":"movie","libItemTimeOffset":10000}}
        """)
        let search = try json(#"{"extra":[["search","night of the living dead"]],"type":null}"#)
        #expect(Fixture.inRelease { RedactedMask.json(event).compactDescription } == """
        {"context":{"libItemID":"#u6bvt2","libItemName":"#eql2ul","libItemTimeOffset":10000,"libItemType":"movie"}}
        """)
        #expect(Fixture.inRelease { RedactedMask.json(search).compactDescription } == ##"{"extra":[["#cyckex","#ctmmqy"]],"type":null}"##)
    }

    @Test func debugShowsJSONAsItIs() throws {
        #expect(try RedactedMask.json(json(#"{"libItemID":"tt0063350"}"#)).compactDescription == #"{"libItemID":"tt0063350"}"#)
    }

    @Test(arguments: [
        ("Night of the Living Dead", "Night of the Living Dead"),
        ("https://torrentio.strem.fun/realdebrid=0123456789abcdefghijABCDEFGHIJ/manifest.json", "https://torrentio.strem.fun/…"),
        (#"{"url":"https:\/\/real-debrid.com\/d\/K7FM\/movie.mkv","name":"Torrentio"}"#, #"{"url":"https://real-debrid.com/…","name":"Torrentio"}"#),
        ("authKey 0123456789abcdefghijABCDEFGHIJ_-xyz", "authKey …"),
    ])
    func legendRevealsNothingThatGrantsAccess(value: String, legend: String) {
        #expect(RedactedMask.legendText(of: value) == legend)
    }
}
