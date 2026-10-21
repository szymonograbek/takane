import Foundation

/// The core models the bridge exposes. Raw values match `AppModelField` in core/src/model.rs.
enum CoreField: String, Codable, Sendable {
    case ctx
    case continueWatchingPreview = "continue_watching_preview"
    case addonDetails = "addon_details"
    case board
    case search
    case discover
    case metaDetails = "meta_details"
    case player
    case link
    case library
    case calendar
}

/// Actions the app sends to stremio-core, encoded in core's `Action` JSON shape
/// (`{"action": <name>, "args": <payload>}`, nested per sub-enum).
/// core/src/lib.rs has a test that parses these exact shapes.
enum CoreAction: Sendable {
    case load(Load)
    case catalogs(Catalogs)
    case library(Library)
    case ctx(Ctx)
    case player(Player)
    case link(Link)
    case metaDetails(MetaDetails)
    case unload

    enum Load: Sendable {
        case addonDetails(transportURL: URL)
        case catalogsWithExtra(CatalogsSelection)
        /// One catalog, such as a catalog filtered by a genre.
        case catalogWithFilters(ResourceRequest)
        case metaDetails(metaPath: ResourcePath, streamPath: ResourcePath?)
        /// Core's player selection, as `CoreStreamService` built it into a candidate's tracking token.
        case player(selection: JSONValue)
        /// Requests a new sign-in code.
        case link
        /// The library's first page for the request.
        case libraryWithFilters(LibraryRequest)
        /// The library's shows with their videos. Core asks the add-ons only while it holds none,
        /// so reloading means unloading first.
        case calendar
    }

    /// Paging of the `CatalogsWithExtra` model the action targets.
    enum Catalogs: Sendable {
        /// Requests the catalogs at these indices that are not requested yet.
        case loadRange(Range<Int>)
        /// Requests the next page of the catalog at this index, if its last page loaded and it pages.
        case loadNextPage(index: Int)
    }

    /// Paging of the `LibraryWithFilters` model.
    enum Library: Sendable {
        /// Adds the next page to the loaded ones, if there is one.
        case loadNextPage
    }

    enum Ctx: Sendable {
        case installAddon(descriptor: JSONValue)
        case uninstallAddon(descriptor: JSONValue)
        case authenticate(Authentication)
        case logout
        /// Core's whole `Settings` object, as read from the profile with some keys changed.
        case updateSettings(JSONValue)
        /// Resets a library item's progress, which takes it out of continue watching.
        case rewindLibraryItem(id: String)
        /// Marks a library item as a whole. Core ignores an id not in the library.
        case libraryItemMarkAsWatched(id: String, isWatched: Bool)
        /// Forgets the new episodes found for a title, which takes it out of continue watching.
        case dismissNotificationItem(id: String)
        /// Asks add-ons for episodes of the library's shows newer than the one watched last.
        /// Core asks at most every 6 hours.
        case pullNotifications
        /// Refreshes the signed-in user and signs out if the session expired.
        case pullUserFromAPI
        case pullAddonsFromAPI
        /// Pulls library items changed elsewhere and pushes the ones changed here.
        case syncLibraryWithAPI
        case clearSearchHistory
        /// Adds the title to the library, or brings back one removed from it.
        case addToLibrary(MetaPreview)
        case removeFromLibrary(id: String)
    }

    /// Watched marks on the title the `meta_details` model holds, through its library item.
    enum MetaDetails: Sendable {
        case markAsWatched(Bool)
        /// core's full video JSON, as the model's first ready meta item lists it.
        case markVideoAsWatched(video: JSONValue, Bool)
        case markSeasonAsWatched(UInt32, Bool)
    }

    /// core's `AuthRequest`.
    enum Authentication: Sendable {
        case login(email: String, password: String)
        case loginWithToken(String)
    }

    enum Link: Sendable {
        /// Asks whether the current code was confirmed; the answer lands in the `link` model.
        case readData
    }

    enum Player: Sendable {
        case timeChanged(timeMs: UInt64, durationMs: UInt64, device: String)
        /// Moves core's position without counting the skipped time as watched, which `timeChanged` would.
        case seek(timeMs: UInt64, durationMs: UInt64, device: String)
        case pausedChanged(paused: Bool)
        case ended
        /// Records moving on to the player model's next video. Loading it is a separate `Load`.
        case nextVideo
        /// What subtitle add-ons match the file by. Core prefers what the stream itself declares.
        case videoParamsChanged(hash: String?, size: UInt64?, filename: String?)
        /// Replaces what core saves for the selected video.
        case streamStateChanged(StreamItemState)
    }
}

// MARK: - Encoding

/// `{"action": name}` or `{"action": name, "args": args}`.
private struct Tagged<Args: Encodable>: Encodable {
    let name: String
    let args: Args?
    let tagKey: String
    let argsKey: String

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encode(name, forKey: DynamicKey(tagKey))
        if let args {
            try container.encode(args, forKey: DynamicKey(argsKey))
        }
    }
}

/// A JSON object key known only at run time.
struct DynamicKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private struct NoArgs: Encodable {}

private func action<Args: Encodable>(_ name: String, _ args: Args) -> Tagged<Args> {
    Tagged(name: name, args: args, tagKey: "action", argsKey: "args")
}

private func action(_ name: String) -> Tagged<NoArgs> {
    Tagged(name: name, args: nil, tagKey: "action", argsKey: "args")
}

private func model<Args: Encodable>(_ name: String, _ args: Args) -> Tagged<Args> {
    Tagged(name: name, args: args, tagKey: "model", argsKey: "args")
}

private func model(_ name: String) -> Tagged<NoArgs> {
    Tagged(name: name, args: nil, tagKey: "model", argsKey: "args")
}

extension CoreAction: Encodable {
    func encode(to encoder: any Encoder) throws {
        switch self {
        case .load(let load): try action("Load", load).encode(to: encoder)
        case .catalogs(let catalogs): try action("CatalogsWithExtra", catalogs).encode(to: encoder)
        case .library(.loadNextPage): try action("LibraryWithFilters", action("LoadNextPage")).encode(to: encoder)
        case .ctx(let ctx): try action("Ctx", ctx).encode(to: encoder)
        case .player(let player): try action("Player", player).encode(to: encoder)
        case .link(.readData): try action("Link", action("ReadData")).encode(to: encoder)
        case .metaDetails(let metaDetails): try action("MetaDetails", metaDetails).encode(to: encoder)
        case .unload: try action("Unload").encode(to: encoder)
        }
    }
}

extension CoreAction.Load: Encodable {
    private struct AddonDetailsArgs: Encodable { let transportUrl: URL }
    private struct MetaDetailsArgs: Encodable {
        let metaPath: ResourcePath
        let streamPath: ResourcePath?
        let guessStream: Bool
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .addonDetails(let url):
            try model("AddonDetails", AddonDetailsArgs(transportUrl: url)).encode(to: encoder)
        case .catalogsWithExtra(let selection):
            try model("CatalogsWithExtra", selection).encode(to: encoder)
        case .catalogWithFilters(let request):
            try model("CatalogWithFilters", ["request": request]).encode(to: encoder)
        case .metaDetails(let metaPath, let streamPath):
            try model("MetaDetails", MetaDetailsArgs(metaPath: metaPath, streamPath: streamPath, guessStream: false))
                .encode(to: encoder)
        case .player(let selection):
            try model("Player", selection).encode(to: encoder)
        case .link:
            try model("Link").encode(to: encoder)
        case .libraryWithFilters(let request):
            try model("LibraryWithFilters", ["request": request]).encode(to: encoder)
        case .calendar:
            // No month: core picks the current one, which the app does not use.
            try model("Calendar", JSONValue.null).encode(to: encoder)
        }
    }
}

extension CoreAction.Catalogs: Encodable {
    private struct RangeArgs: Encodable { let start: Int; let end: Int }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .loadRange(let range):
            // core's range includes `end`; one index past the last catalog requests nothing more.
            try action("LoadRange", RangeArgs(start: range.lowerBound, end: range.upperBound)).encode(to: encoder)
        case .loadNextPage(let index):
            try action("LoadNextPage", index).encode(to: encoder)
        }
    }
}

extension CoreAction.Ctx: Encodable {
    func encode(to encoder: any Encoder) throws {
        switch self {
        case .installAddon(let descriptor): try action("InstallAddon", descriptor).encode(to: encoder)
        case .uninstallAddon(let descriptor): try action("UninstallAddon", descriptor).encode(to: encoder)
        case .authenticate(let request): try action("Authenticate", request).encode(to: encoder)
        case .logout: try action("Logout").encode(to: encoder)
        case .updateSettings(let settings): try action("UpdateSettings", settings).encode(to: encoder)
        case .rewindLibraryItem(let id): try action("RewindLibraryItem", id).encode(to: encoder)
        case .libraryItemMarkAsWatched(let id, let isWatched):
            try action("LibraryItemMarkAsWatched", MarkAsWatchedArgs(id: id, isWatched: isWatched)).encode(to: encoder)
        case .dismissNotificationItem(let id): try action("DismissNotificationItem", id).encode(to: encoder)
        case .pullNotifications: try action("PullNotifications").encode(to: encoder)
        // No token: core uses the profile's.
        case .pullUserFromAPI: try action("PullUserFromAPI", NoArgs()).encode(to: encoder)
        case .pullAddonsFromAPI: try action("PullAddonsFromAPI").encode(to: encoder)
        case .syncLibraryWithAPI: try action("SyncLibraryWithAPI").encode(to: encoder)
        case .clearSearchHistory: try action("ClearSearchHistory").encode(to: encoder)
        case .addToLibrary(let title): try action("AddToLibrary", MetaItemPreviewArgs(title)).encode(to: encoder)
        case .removeFromLibrary(let id): try action("RemoveFromLibrary", id).encode(to: encoder)
        }
    }

    /// The part of core's `MetaItemPreview` its library item keeps.
    private struct MetaItemPreviewArgs: Encodable {
        let id: String
        let type: String
        let name: String
        let poster: URL?
        let posterShape: String
        let background: URL?
        let logo: URL?

        init(_ title: MetaPreview) {
            id = title.media.rawValue
            type = title.type.rawValue
            name = title.name.rawValue
            poster = title.poster
            posterShape = title.posterShape.coreName
            background = title.background
            logo = title.logo
        }
    }

    private struct MarkAsWatchedArgs: Encodable {
        let id: String
        let isWatched: Bool

        private enum CodingKeys: String, CodingKey {
            case id
            case isWatched = "is_watched"
        }
    }
}

extension CoreAction.MetaDetails: Encodable {
    /// A Rust tuple variant's arguments: a JSON array.
    private struct Pair<First: Encodable, Second: Encodable>: Encodable {
        let first: First
        let second: Second

        init(_ first: First, _ second: Second) {
            self.first = first
            self.second = second
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(first)
            try container.encode(second)
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .markAsWatched(let isWatched):
            try action("MarkAsWatched", isWatched).encode(to: encoder)
        case .markVideoAsWatched(let video, let isWatched):
            try action("MarkVideoAsWatched", Pair(video, isWatched)).encode(to: encoder)
        case .markSeasonAsWatched(let season, let isWatched):
            try action("MarkSeasonAsWatched", Pair(season, isWatched)).encode(to: encoder)
        }
    }
}

extension CoreAction.Player: Encodable {
    private struct TimeArgs: Encodable { let time: UInt64; let duration: UInt64; let device: String }
    private struct PausedChangedArgs: Encodable { let paused: Bool }
    private struct VideoParamsChangedArgs: Encodable {
        struct VideoParams: Encodable {
            let hash: String?
            let size: UInt64?
            let filename: String?
        }

        let videoParams: VideoParams
    }
    private struct StreamStateChangedArgs: Encodable { let state: StreamItemState }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .timeChanged(let time, let duration, let device):
            try action("TimeChanged", TimeArgs(time: time, duration: duration, device: device)).encode(to: encoder)
        case .seek(let time, let duration, let device):
            try action("Seek", TimeArgs(time: time, duration: duration, device: device)).encode(to: encoder)
        case .pausedChanged(let paused):
            try action("PausedChanged", PausedChangedArgs(paused: paused)).encode(to: encoder)
        case .ended:
            try action("Ended").encode(to: encoder)
        case .nextVideo:
            try action("NextVideo").encode(to: encoder)
        case .videoParamsChanged(let hash, let size, let filename):
            let params = VideoParamsChangedArgs.VideoParams(hash: hash, size: size, filename: filename)
            try action("VideoParamsChanged", VideoParamsChangedArgs(videoParams: params)).encode(to: encoder)
        case .streamStateChanged(let state):
            try action("StreamStateChanged", StreamStateChangedArgs(state: state)).encode(to: encoder)
        }
    }
}

extension CoreAction.Authentication: Encodable {
    private struct Login: Encodable {
        let type = "Login"
        let email: String
        let password: String
        let facebook = false
    }

    private struct LoginWithToken: Encodable {
        let type = "LoginWithToken"
        let token: String
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .login(let email, let password): try Login(email: email, password: password).encode(to: encoder)
        case .loginWithToken(let token): try LoginWithToken(token: token).encode(to: encoder)
        }
    }
}
