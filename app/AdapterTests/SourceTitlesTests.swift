import Foundation
import Testing

/// A source's titles across its libraries, as Library lists them, from the recorded Jellyfin
/// answers and from WebDAV listings written here.
struct SourceTitlesTests {
    @Test func theSourcesTitlesListAcrossItsLibrariesByTypeInTheOrderAsked() async throws {
        let index = try await JellyfinAddonTests.addon(HTTPStub(JellyfinAddonTests.server())).index()
        func names(_ type: ContentType?, _ sort: SourceSort) -> [String] {
            index.titles(of: type, sortedBy: sort).map(\.name.rawValue)
        }

        #expect(names(nil, .recentlyAdded) == ["Pioneer One", "Beach Day", "Elephants Dream", "Tears of Steel", "Big Buck Bunny", "Sintel"])
        #expect(names(nil, .name) == ["Beach Day", "Big Buck Bunny", "Elephants Dream", "Pioneer One", "Sintel", "Tears of Steel"])
        #expect(names(nil, .year) == ["Tears of Steel", "Pioneer One", "Sintel", "Big Buck Bunny", "Elephants Dream", "Beach Day"])
        #expect(names(.movie, .name) == ["Beach Day", "Big Buck Bunny", "Elephants Dream", "Sintel", "Tears of Steel"])
        #expect(names(.series, .recentlyAdded) == ["Pioneer One"])
    }

    @Test func aShowCountsAsAddedWhenItsNewestEpisodeWas() async throws {
        let olderShow = JellyfinAddonTests.server { name, body in
            name == "jellyfin-items-shows" ? body.replacingOccurrences(of: "2026-10-23T10:55:45.5097094Z", with: "2020-01-01T00:00:00Z") : body
        }
        let index = try await JellyfinAddonTests.addon(HTTPStub(olderShow)).index()

        #expect(index.titles(of: nil, sortedBy: .recentlyAdded).prefix(3).map(\.name.rawValue) == ["Beach Day", "Pioneer One", "Elephants Dream"])
    }

    @Test func aTitleInTwoFoldersIsListedOnceWhereTheSortPutsItFirst() async throws {
        let addon = Subject.addon(HTTPStub(Subject.listing([
            "/Movies/", "/Movies/Sintel [imdbid-tt1727587].mkv", "/Films/", "/Films/Sintel (2010) [imdbid-tt1727587].mp4", "/Films/Beach Day.mp4",
        ])))

        let byName = try await addon.index().titles(of: .movie, sortedBy: .name)
        let byYear = try await addon.index().titles(of: .movie, sortedBy: .year)

        #expect(byName.map(\.id.rawValue).filter { $0 == "tt1727587" }.count == 1)
        #expect(byName.count == 2)
        #expect(byYear.first?.year == 2010)
    }

    @Test func copiesOfATitleInOneFolderTakeTheYearOneOfThemIsNamedWith() async throws {
        let addon = Subject.addon(HTTPStub(Subject.listing([
            "/Movies/", "/Movies/Sintel [imdbid-tt1727587].mkv", "/Movies/Sintel (2010) [imdbid-tt1727587].mp4",
        ])))

        let titles = try await addon.index().titles(of: nil, sortedBy: .year)

        #expect(titles.map(\.year) == [2010])
    }
}
