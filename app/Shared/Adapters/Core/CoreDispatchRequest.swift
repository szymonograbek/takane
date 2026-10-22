import Foundation

/// Requests about what core does not know, which the bridge handles itself (`BridgeRequest` in
/// core/src/lib.rs, whose tests parse these shapes).
enum BridgeRequest: Sendable {
    /// Switches an add-on on or off on this device only. The bridge keeps the off ones from every
    /// core model but `ctx`, which still holds and syncs them.
    case setAddonEnabled(transportURL: URL, isEnabled: Bool)
    /// Lists the installed add-ons in this order on the account and syncs it, as core syncs an
    /// install. Core has no action for it.
    case setAddonOrder(transportURLs: [URL])
}

/// The JSON document `sb_dispatch` accepts: a core action for one model, or for all with no
/// field, or a bridge request.
enum DispatchRequest: Sendable {
    case core(CoreAction, to: CoreField?)
    case bridge(BridgeRequest)

    /// Carries a password or token, so logs show only its name.
    var isSensitive: Bool {
        if case .core(.ctx(.authenticate), _) = self { true } else { false }
    }
}

extension DispatchRequest: Encodable {
    private enum CodingKeys: String, CodingKey { case action, field }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .core(let action, let field):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(action, forKey: .action)
            // core expects an explicit null when no field is targeted.
            try container.encode(field, forKey: .field)
        case .bridge(let request):
            try request.encode(to: encoder)
        }
    }
}

extension BridgeRequest: Encodable {
    private enum CodingKeys: String, CodingKey { case setAddonEnabled, setAddonOrder }
    private struct SetAddonEnabledArgs: Encodable {
        let transportUrl: URL
        let enabled: Bool
    }
    private struct SetAddonOrderArgs: Encodable {
        let transportUrls: [URL]
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .setAddonEnabled(let url, let isEnabled):
            try container.encode(SetAddonEnabledArgs(transportUrl: url, enabled: isEnabled), forKey: .setAddonEnabled)
        case .setAddonOrder(let urls):
            try container.encode(SetAddonOrderArgs(transportUrls: urls), forKey: .setAddonOrder)
        }
    }
}
