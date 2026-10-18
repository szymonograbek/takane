import Foundation
import Libmpv

/// Reads mpv's `track-list` node: an array of maps with `id`, `type` (`audio`, `sub`, `video`),
/// `title`, `lang`, `codec`, `demux-channel-count`, `forced`, `external-filename` and `selected`.
enum MPVTrackList {
    static func tracks(in list: mpv_node) -> [MediaTrack] {
        guard list.format == MPV_FORMAT_NODE_ARRAY, let array = list.u.list?.pointee, let values = array.values else { return [] }
        return (0..<Int(array.num)).compactMap { track(values[$0]) }
    }

    private static func track(_ node: mpv_node) -> MediaTrack? {
        guard node.format == MPV_FORMAT_NODE_MAP, let map = node.u.list?.pointee, let keys = map.keys, let values = map.values else { return nil }
        var fields: [String: mpv_node] = [:]
        for index in 0..<Int(map.num) {
            if let key = keys[index] { fields[String(cString: key)] = values[index] }
        }
        let kind: TrackKind
        switch fields["type"].flatMap(string) {
        case "audio": kind = .audio
        case "sub": kind = .subtitle
        default: return nil
        }
        guard let number = fields["id"].flatMap(int) else { return nil }
        return MediaTrack(
            id: MediaTrack.ID(kind: kind, number: number),
            title: fields["title"].flatMap(string),
            language: fields["lang"].flatMap(string),
            codec: fields["codec"].flatMap(string),
            channelCount: fields["demux-channel-count"].flatMap(int),
            isForced: isSet(fields["forced"]),
            externalFile: fields["external-filename"].flatMap(string).flatMap { URL(string: $0) },
            isSelected: isSet(fields["selected"])
        )
    }

    private static func string(_ node: mpv_node) -> String? {
        guard node.format == MPV_FORMAT_STRING, let text = node.u.string else { return nil }
        return String(cString: text)
    }

    private static func int(_ node: mpv_node) -> Int? {
        node.format == MPV_FORMAT_INT64 ? Int(node.u.int64) : nil
    }

    /// A missing flag is unset.
    private static func isSet(_ node: mpv_node?) -> Bool {
        guard let node, node.format == MPV_FORMAT_FLAG else { return false }
        return node.u.flag != 0
    }
}
