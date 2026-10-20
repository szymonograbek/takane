import Foundation

/// Subtitles from the user's add-ons through core's `player` model, which `CorePlaybackTracker`
/// loads with the candidate's subtitles path.
///
/// Core asks the add-ons once it knows the file: from the stream's own hints, and again after
/// `VideoParamsChanged` reports the OpenSubtitles hash and size this adapter reads from the
/// stream. Add-ons that time subtitles to the file need those to tell this copy apart.
struct CoreSubtitleService: SubtitleService {
    let runtime: CoreRuntime
    var session = URLSession.shared

    func subtitles(for candidate: StreamCandidate, playing source: PlaybackSource) -> AsyncStream<[SubtitleSource]> {
        let (results, continuation) = AsyncStream.makeStream(of: [SubtitleSource].self, bufferingPolicy: .bufferingNewest(1))
        // Subscribe before reporting the file so no answer is missed.
        let states = runtime.states(.player, as: PlayerState.self)
        let runtime = runtime
        let session = session
        let reporting = Task {
            let fingerprint: VideoFingerprint?
            do {
                fingerprint = try await session.fingerprint(of: source)
            } catch {
                Log.core.warning("fingerprinting \(candidate.item) failed: \(error)")
                fingerprint = nil
            }
            guard !Task.isCancelled else { return }
            Log.core.info("video params for \(candidate.item): hash \(fingerprint.map { "\(Redacted($0.hash))" } ?? "-"), size \(fingerprint?.size ?? 0)")
            runtime.dispatchLogged(
                .player(.videoParamsChanged(hash: fingerprint?.hash, size: fingerprint?.size, filename: candidate.filename?.rawValue)),
                to: .player
            )
        }
        let listening = Task {
            var isSelected = false
            for await player in states {
                guard player.plays(candidate, from: source) else {
                    // Before the tracker's load lands nothing is selected; after, another candidate replaced this one.
                    if isSelected { break } else { continue }
                }
                isSelected = true
                continuation.yield(Self.sources(from: player, addonNames: runtime.addonNames()))
            }
            reporting.cancel()
            continuation.finish()
        }
        continuation.onTermination = { _ in
            reporting.cancel()
            listening.cancel()
        }
        return results
    }

    private static func sources(from player: PlayerState, addonNames: [URL: Redacted<String>]) -> [SubtitleSource] {
        player.subtitles.compactMap { loadable -> SubtitleSource? in
            guard let addon = ManifestURL(loadable.request.base) else { return nil }
            let subtitles: Remote<[AddonSubtitle], SubtitleSourceError> = switch loadable.content {
            case .none, .loading:
                .loading
            case .ready(let files):
                .loaded(files.compactMap { file in
                    URL(string: file.url).map {
                        AddonSubtitle(
                            id: AddonSubtitle.ID(addon: addon, key: Redacted(file.id)), url: Redacted($0),
                            language: file.lang, label: file.label.map(Redacted.init)
                        )
                    }
                })
            case .failed(let error):
                .failed(.addonFailed(reason: error.compactDescription))
            }
            let name = addonNames[addon.url.rawValue] ?? Redacted(addon.url.rawValue.host() ?? "?")
            return SubtitleSource(addon: addon, addonName: name, subtitles: subtitles)
        }
    }
}
