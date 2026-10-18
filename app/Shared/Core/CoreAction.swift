import Foundation

/// The core models the bridge exposes. Raw values match `AppModelField` in core/src/model.rs.
enum CoreField: String, Codable, Sendable, CaseIterable {
    case ctx
    case continueWatchingPreview = "continue_watching_preview"
    case addonDetails = "addon_details"
    case metaDetails = "meta_details"
    case player
}

/// Actions the app sends to stremio-core, encoded in core's `Action` JSON shape
/// (`{"action": <name>, "args": <payload>}`, nested per sub-enum).
/// core/src/lib.rs has a test that parses these exact shapes.
enum CoreAction: Sendable {
    case load(Load)
    case ctx(Ctx)
    case player(Player)
    case unload

    enum Load: Sendable {
        case addonDetails(transportURL: URL)
        case metaDetails(metaPath: ResourcePath, streamPath: ResourcePath?)
        case player(PlayerSelection)
    }

    enum Ctx: Sendable {
        case installAddon(descriptor: JSONValue)
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

struct ResourceRequest: Codable, Hashable, Sendable {
    var base: URL
    var path: ResourcePath
}

/// What core's player model needs to track progress for a stream.
struct PlayerSelection: Encodable, Sendable {
    var stream: JSONValue
    var streamRequest: ResourceRequest?
    var metaRequest: ResourceRequest?
    var subtitlesPath: ResourcePath?
}

/// The JSON document `sb_dispatch` accepts.
struct DispatchRequest: Encodable {
    let action: CoreAction
    let field: CoreField?

    func encode(to encoder: Encoder) throws {
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

    func encode(to encoder: Encoder) throws {
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

extension CoreAction: Encodable {
    func encode(to encoder: Encoder) throws {
        switch self {
        case .load(let load): try action("Load", load).encode(to: encoder)
        case .ctx(let ctx): try action("Ctx", ctx).encode(to: encoder)
        case .player(let player): try action("Player", player).encode(to: encoder)
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

    func encode(to encoder: Encoder) throws {
        switch self {
        case .addonDetails(let url):
            try model("AddonDetails", AddonDetailsArgs(transportUrl: url)).encode(to: encoder)
        case .metaDetails(let metaPath, let streamPath):
            try model("MetaDetails", MetaDetailsArgs(metaPath: metaPath, streamPath: streamPath, guessStream: false))
                .encode(to: encoder)
        case .player(let selection):
            try model("Player", selection).encode(to: encoder)
        }
    }
}

extension CoreAction.Ctx: Encodable {
    func encode(to encoder: Encoder) throws {
        switch self {
        case .installAddon(let descriptor): try action("InstallAddon", descriptor).encode(to: encoder)
        }
    }
}

extension CoreAction.Player: Encodable {
    private struct TimeChangedArgs: Encodable { let time: UInt64; let duration: UInt64; let device: String }
    private struct PausedChangedArgs: Encodable { let paused: Bool }

    func encode(to encoder: Encoder) throws {
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
