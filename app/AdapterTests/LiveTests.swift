import Foundation

/// Tests against the real services run only when asked, since they need the network.
enum LiveTests {
    static let enabled = ProcessInfo.processInfo.environment["STREMIO_LIVE_TESTS"] == "1"
}
