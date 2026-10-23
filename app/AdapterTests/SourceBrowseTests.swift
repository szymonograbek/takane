import Foundation
import Testing

/// Browsing a source's folders, read from the same listings its add-on answers core from.
struct SourceBrowseTests {
    @Test func browsingWalksTheLibrariesThenTheirFoldersToTheirTitles() async throws {
        let summer = "5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c"
        // The dev server has no folder inside a library: put Beach Day in one.
        let addon = JellyfinAddonTests.addon(HTTPStub(JellyfinAddonTests.server { name, body in
            guard name == "jellyfin-items-home-videos" else { return body }
            let folder = #"{"Name":"Summer","Id":"\#(summer)","ParentId":"2b0cf6096f0c275a4f3b6ee15ea8bb10","Type":"Folder"},"#
            return body
                .replacingOccurrences(of: #""ParentId":"2b0cf6096f0c275a4f3b6ee15ea8bb10","Type":"Video""#, with: #""ParentId":"\#(summer)","Type":"Video""#)
                .replacingOccurrences(of: #"{"Items":["#, with: #"{"Items":["# + folder)
        }))

        let root = try await addon.browse(nil)
        let homeVideos = try await addon.browse(SourceFolderID("f4415c72cc16920fce19d78d636a3ce7"))
        let inSummer = try await addon.browse(SourceFolderID(summer))
        let movies = try await addon.browse(SourceFolderID("f137a2dd21bbc1b99aa5c0f6bf02a805"))
        let shows = try await addon.browse(SourceFolderID("a656b907eb3a73532e40e44b968d0225"))

        #expect(root == [
            .folder(SourceFolderID("f4415c72cc16920fce19d78d636a3ce7"), name: Redacted("Home Videos")),
            .folder(SourceFolderID("f137a2dd21bbc1b99aa5c0f6bf02a805"), name: Redacted("Movies")),
            .folder(SourceFolderID("a656b907eb3a73532e40e44b968d0225"), name: Redacted("Shows")),
        ])
        #expect(homeVideos == [.folder(SourceFolderID(summer), name: Redacted("Summer"))])
        guard case .title(let beachDay) = try #require(inSummer.first) else { throw BrowseFailure.notATitle }
        #expect(inSummer.count == 1)
        #expect(beachDay.media.rawValue == JellyfinAddonTests.local + JellyfinAddonTests.beachDay)
        #expect(beachDay.posterShape == .landscape)
        #expect(Set(movies.compactMap(\.media)) == ["tt1727587", "tt1254207", "tt2285752", "tt0807840"])
        #expect(shows.compactMap(\.media) == ["tt1748166"])
        await #expect(throws: SourceError.folderGone) { try await addon.browse(SourceFolderID("2b0cf6096f0c275a4f3b6ee15ea8bb10")) }
    }

    @Test func browsingWalksTheFoldersAndShowsAMoviesFolderAsTheMovie() async throws {
        let addon = Subject.addon(HTTPStub(Subject.devServer))

        let root = try await addon.browse(nil)
        let folders = Dictionary(root.compactMap { entry -> (String, SourceFolderID)? in
            if case .folder(let id, let name) = entry { (name.rawValue, id) } else { nil }
        }) { first, _ in first }
        let moviesFolder: SourceFolderID = try #require(folders["Movies"])
        let showsFolder: SourceFolderID = try #require(folders["Shows"])
        let homeVideosFolder: SourceFolderID = try #require(folders["Home Videos"])
        let movies = try await addon.browse(moviesFolder)
        let shows = try await addon.browse(showsFolder)
        guard case .folder(let pioneerOne, let showName) = try #require(shows.first) else { throw BrowseFailure.notAFolder }
        guard case .folder(let season, let seasonName) = try #require(try await addon.browse(pioneerOne).first) else { throw BrowseFailure.notAFolder }
        let episodes = try await addon.browse(season)
        let homeVideos = try await addon.browse(homeVideosFolder)

        #expect(root.count == 3 && folders.keys.sorted() == ["Home Videos", "Movies", "Shows"])
        #expect(movies.compactMap(\.media) == ["tt1254207", "tt0807840", "tt1727587", "tt2285752"])
        #expect(shows.count == 1 && showName.rawValue == "Pioneer One (2010) [imdbid-tt1748166]")
        #expect(seasonName.rawValue == "Season 01")
        #expect(episodes.map(\.episodeNumber) == [1, 2, 3])
        #expect(episodes.allSatisfy { $0.media == "tt1748166" })
        guard case .title(let beachDay) = try #require(homeVideos.first) else { throw BrowseFailure.notATitle }
        #expect(beachDay.media.rawValue.hasPrefix(Subject.local) && beachDay.name.rawValue == "Beach Day")
        await #expect(throws: SourceError.folderGone) { try await addon.browse(SourceFolderID("gone")) }
    }
}

private enum BrowseFailure: Error {
    case notAFolder, notATitle
}

private extension SourceEntry {
    /// The id of the title it opens, as text.
    var media: String? {
        switch self {
        case .folder: nil
        case .title(let preview), .episode(let preview, _, _, _): preview.media.rawValue
        }
    }

    var episodeNumber: Int? {
        if case .episode(_, _, let episode, _) = self { episode } else { nil }
    }
}
