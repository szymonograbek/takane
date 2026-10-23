import Foundation
import Testing

struct CoreCatalogWireTests {
    @Test func genreTitlesLoadTheShapeCoreParses() throws {
        let request = ResourceRequest(
            base: try #require(URL(string: "https://v3-cinemeta.strem.io/manifest.json")),
            path: .catalog(type: "movie", id: "top", extra: [["genre", "Action"]])
        )
        let encoded = try JSONEncoder().encode(DispatchRequest.core(.load(.catalogWithFilters(request)), to: .discover))

        // The literal core/src/lib.rs parses as a core action.
        let expected = #"""
        {"field":"discover","action":{"action":"Load","args":{"model":"CatalogWithFilters","args":{"request":{
            "base":"https://v3-cinemeta.strem.io/manifest.json",
            "path":{"resource":"catalog","type":"movie","id":"top","extra":[["genre","Action"]]}
        }}}}}
        """#
        #expect(try JSONDecoder().decode(JSONValue.self, from: encoded) == JSONDecoder().decode(JSONValue.self, from: Data(expected.utf8)))
    }

    @Test func addonSwitchEncodesTheShapeTheBridgeParses() throws {
        let url = try #require(URL(string: "https://example.com/manifest.json"))
        let encoded = try JSONEncoder().encode(DispatchRequest.bridge(.setAddonEnabled(transportURL: url, isEnabled: false)))

        // The literal core/src/lib.rs parses as a bridge request.
        let expected = #"{"setAddonEnabled":{"transportUrl":"https://example.com/manifest.json","enabled":false}}"#
        #expect(try JSONDecoder().decode(JSONValue.self, from: encoded) == JSONDecoder().decode(JSONValue.self, from: Data(expected.utf8)))
    }

    @Test func addonOrderEncodesTheShapeTheBridgeParses() throws {
        let first = try #require(URL(string: "https://two.example/manifest.json"))
        let second = try #require(URL(string: "https://example.com/manifest.json"))
        let encoded = try JSONEncoder().encode(DispatchRequest.bridge(.setAddonOrder(transportURLs: [first, second])))

        // The literal core/src/lib.rs parses as a bridge request.
        let expected = #"{"setAddonOrder":{"transportUrls":["https://two.example/manifest.json","https://example.com/manifest.json"]}}"#
        #expect(try JSONDecoder().decode(JSONValue.self, from: encoded) == JSONDecoder().decode(JSONValue.self, from: Data(expected.utf8)))
    }

    @Test func ctxCarriesSearchHistoryDisabledAddonsAndCatalogExtras() throws {
        let json = #"""
        {
            "profile": {
                "auth": null,
                "settings": {},
                "addons": [{
                    "transportUrl": "https://v3-cinemeta.strem.io/manifest.json",
                    "manifest": {
                        "id": "com.linvo.cinemeta", "name": "Cinemeta", "version": "3.0.0",
                        "catalogs": [
                            {"id": "top", "type": "movie", "name": "Popular", "extra": [
                                {"name": "genre", "isRequired": false, "options": ["Action", "Drama"], "optionsLimit": 1},
                                {"name": "skip", "isRequired": false, "options": [], "optionsLimit": 1}
                            ]},
                            {"id": "legacy", "type": "series", "extraRequired": ["search"], "extraSupported": ["search", "skip"]}
                        ]
                    }
                }]
            },
            "searchHistory": ["breaking bad", "twin peaks"],
            "disabledAddons": ["https://off.example/manifest.json"]
        }
        """#
        let state = try JSONDecoder().decode(CtxState.self, from: Data(json.utf8))
        let catalogs = try #require(state.profile.addons.first).manifest.catalogs

        #expect(state.searchHistory == ["breaking bad", "twin peaks"])
        #expect(state.disabledAddons == [try #require(URL(string: "https://off.example/manifest.json"))])
        #expect(state.enabledAddons.map(\.transportUrl.absoluteString) == ["https://v3-cinemeta.strem.io/manifest.json"])
        #expect(catalogs.map { $0.extra.map(\.name) } == [["genre", "skip"], ["search", "skip"]])
        #expect(catalogs.map { $0.extra.map(\.isRequired) } == [[false, false], [true, false]])
        #expect(catalogs[0].extra[0].options == ["Action", "Drama"])
    }
}
