import Foundation

/// The core models the bridge exposes. Raw values match `AppModelField` in core/src/model.rs.
enum CoreField: String, Codable, Sendable {
    case ctx
    case continueWatchingPreview = "continue_watching_preview"
    case addonDetails = "addon_details"
    case board
    case search
    case metaDetails = "meta_details"
    case player
    case link
}

/// Actions the app sends to stremio-core, encoded in core's `Action` JSON shape
/// (`{"action": <name>, "args": <payload>}`, nested per sub-enum).
/// core/src/lib.rs has a test that parses these exact shapes.
enum CoreAction: Sendable {
    case load(Load)
    case catalogs(Catalogs)
    case ctx(Ctx)
    case player(Player)
    case link(Link)
    case unload

    enum Load: Sendable {
        case addonDetails(transportURL: URL)
        case catalogsWithExtra(CatalogsSelection)
        case metaDetails(metaPath: ResourcePath, streamPath: ResourcePath?)
        /// Core's player selection, as `CoreStreamService` built it into a candidate's tracking token.
        case player(selection: JSONValue)
        /// Requests a new sign-in code.
        case link
    }

    /// Paging of the `CatalogsWithExtra` model the action targets.
    enum Catalogs: Sendable {
        /// Requests the catalogs at these indices that are not requested yet.
        case loadRange(Range<Int>)
        /// Requests the next page of the catalog at this index, if its last page loaded and it pages.
        case loadNextPage(index: Int)
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
        case pausedChanged(paused: Bool)
        case ended
    }
}

struct ResourcePath: Codable, Hashable, Sendable {
    var resource: String
    var type: String
    var id: String
    var extra: [[String]] = []

    static func meta(type: String, id: String) -> ResourcePath {
        ResourcePath(resource: "meta", type: type, id: id)
    }

    static func stream(type: String, id: String) -> ResourcePath {
        ResourcePath(resource: "stream", type: type, id: id)
    }
}

/// core's `catalogs_with_extra::Selected`: which catalogs a `CatalogsWithExtra` model loads.
struct CatalogsSelection: Codable, Equatable, Sendable {
    /// Every type when nil.
    var type: String?
    /// `[name, value]` pairs, such as `["search", "shawshank"]`.
    var extra: [[String]]

    /// Every catalog without a required extra.
    static let board = CatalogsSelection(type: nil, extra: [])

    /// Every catalog that supports the `search` extra, asked for `text`.
    static func search(_ text: SearchText) -> CatalogsSelection {
        CatalogsSelection(type: nil, extra: [["search", text.rawValue]])
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // core expects an explicit null for every type.
        try container.encode(type, forKey: .type)
        try container.encode(extra, forKey: .extra)
    }

    private enum CodingKeys: String, CodingKey { case type, extra }
}

struct ResourceRequest: Codable, Hashable, Sendable {
    var base: URL
    var path: ResourcePath
}

extension ResourcePath {
    var json: JSONValue {
        .object([
            "resource": .string(resource),
            "type": .string(type),
            "id": .string(id),
            "extra": .array(extra.map { .array($0.map(JSONValue.string)) }),
        ])
    }
}

extension ResourceRequest {
    var json: JSONValue {
        .object(["base": .string(base.absoluteString), "path": path.json])
    }
}

/// The JSON document `sb_dispatch` accepts.
struct DispatchRequest: Encodable {
    let action: CoreAction
    let field: CoreField?

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        // core expects an explicit null when no field is targeted.
        try container.encode(field, forKey: .field)
    }

    private enum CodingKeys: String, CodingKey { case action, field }
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

private struct DynamicKey: CodingKey {
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
        case .ctx(let ctx): try action("Ctx", ctx).encode(to: encoder)
        case .player(let player): try action("Player", player).encode(to: encoder)
        case .link(.readData): try action("Link", action("ReadData")).encode(to: encoder)
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
        case .metaDetails(let metaPath, let streamPath):
            try model("MetaDetails", MetaDetailsArgs(metaPath: metaPath, streamPath: streamPath, guessStream: false))
                .encode(to: encoder)
        case .player(let selection):
            try model("Player", selection).encode(to: encoder)
        case .link:
            try model("Link").encode(to: encoder)
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
        }
    }
}

extension CoreAction.Player: Encodable {
    private struct TimeChangedArgs: Encodable { let time: UInt64; let duration: UInt64; let device: String }
    private struct PausedChangedArgs: Encodable { let paused: Bool }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .timeChanged(let time, let duration, let device):
            try action("TimeChanged", TimeChangedArgs(time: time, duration: duration, device: device)).encode(to: encoder)
        case .pausedChanged(let paused):
            try action("PausedChanged", PausedChangedArgs(paused: paused)).encode(to: encoder)
        case .ended:
            try action("Ended").encode(to: encoder)
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

extension CoreAction {
    /// Carries a password or token, so logs show only its name.
    var isSensitive: Bool {
        if case .ctx(.authenticate) = self { true } else { false }
    }
}
