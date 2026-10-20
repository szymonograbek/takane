import Foundation

/// How far back shared logs reach.
enum LogWindow: CaseIterable, Hashable, Sendable {
    case fifteenMinutes
    case oneHour
    case sixHours
    case oneDay
    case sevenDays

    static let `default` = LogWindow.oneHour

    var name: String {
        switch self {
        case .fifteenMinutes: "Last 15 Minutes"
        case .oneHour: "Last Hour"
        case .sixHours: "Last 6 Hours"
        case .oneDay: "Last 24 Hours"
        case .sevenDays: "Last 7 Days"
        }
    }

    /// When the window that ends at `end` starts.
    func start(endingAt end: Date) -> Date {
        let hours: Double = switch self {
        case .fifteenMinutes: 0.25
        case .oneHour: 1
        case .sixHours: 6
        case .oneDay: 24
        case .sevenDays: 7 * 24
        }
        return end.addingTimeInterval(-hours * 3_600)
    }
}

/// Where another device on the network fetches the logs. The address is the access, so it is redacted.
struct LogLink: Hashable, Sendable {
    let url: Redacted<URL>
}

enum LogSharingError: Error, Equatable, Sendable {
    /// The device has no address another device on the network can reach.
    case noLocalNetwork
    case listenerFailed(reason: String)
}

/// Lets a phone or computer on the same network download this device's logs.
protocol LogSharing: Sendable {
    /// Starts sharing the logs written in `window`, each fetch reading them afresh. While already
    /// sharing it keeps the same link and shares `window` from then on.
    func share(_ window: LogWindow) async throws(LogSharingError) -> LogLink

    /// Stops sharing; the link no longer answers. Does nothing while not sharing.
    func stop() async
}
