import Foundation

extension PlayerFeature.State {
    /// Position, duration, phase, video size and decoder, such as
    /// `0:00:10 / 2:22:32 · playing · 1920×1080 · VideoToolbox HEVC (HW)`.
    var statusLine: String {
        let session = session
        var parts = [phaseName]
        if let size = session?.videoSize { parts.append("\(size.width)×\(size.height)") }
        if let decoder = session?.decoder { parts.append(decoder) }
        let time = "\(Self.clock(session?.position ?? .zero)) / \(Self.clock(session?.duration ?? .zero))"
        return ([time] + parts).joined(separator: " · ")
    }

    private static func clock(_ duration: Duration) -> String {
        let total = Int(duration.components.seconds)
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}
