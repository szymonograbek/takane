/// Stremio's own skip times through core's `player` model, for Stremio Premium accounts.
///
/// Core asks Stremio's API by itself, for episodes only, once its player holds the stream, the
/// OpenSubtitles hash `CoreSubtitleService` reports and the duration `CorePlaybackTracker` reports.
/// Core does not show whether it is still asking, so no answer in time reads as no data.
struct CoreSkipSegmentService: SkipSegmentService {
    let runtime: CoreRuntime

    /// Core asks only after the file's hash is read over the network and the duration is reported,
    /// so the answer can trail the start of playback by several seconds.
    private static let timeout = Duration.seconds(30)

    func segments(for item: PlayableID, duration: Duration) async throws(SkipSegmentError) -> SkipSegments {
        let none = SkipSegments(item: item, segments: [], introLengthEstimate: nil)
        guard case .episode = item else { return none }
        let stream = Duration.zero...duration
        let answers = runtime.observe(.player, as: PlayerState.self) { $0.skipSegments(for: item, within: stream) }
        return await withTaskGroup(of: SkipSegments.self) { group in
            group.addTask {
                for await case let found? in answers {
                    return found
                }
                return none
            }
            group.addTask {
                try? await Task.sleep(for: Self.timeout)
                return none
            }
            defer { group.cancelAll() }
            return await group.next() ?? none
        }
    }
}
