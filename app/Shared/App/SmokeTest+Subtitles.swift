extension SmokeTest {
    /// Waits for the add-on's files for the stream playing, then plays the first one as an added track.
    func subtitleSteps(_ manifest: ManifestURL, _ result: inout Result) async throws(Failure) {
        let files = try await app.player.until(timeout: .seconds(60), onTimeout: Failure.timedOut("subtitles from \(manifest)")) { state in
            guard let source = state.session?.addonSubtitles.first(where: { $0.addon == manifest }) else {
                return Probe<[AddonSubtitle], Failure>.pending
            }
            switch source.subtitles {
            case .loading: return .pending
            case .loaded(let files) where files.isEmpty: return .failed(.noSubtitles(addon: source.addonName, nil))
            case .loaded(let files): return .done(files)
            case .failed(let error): return .failed(.noSubtitles(addon: source.addonName, error))
            }
        }
        let session = app.player.state.session
        result.subtitleCounts = Dictionary(
            (session?.addonSubtitles ?? []).map { ($0.addonName, $0.subtitles.value?.count ?? 0) },
            uniquingKeysWith: +
        )
        result.subtitleCounts["built-in"] = session?.builtInSubtitles.count
        result.subtitleLabels = files.prefix(5).map { "\($0.language) \($0.label ?? "")" }
        Log.smoke.info("SMOKE subtitles found: \(result.subtitleCounts); first: \(result.subtitleLabels)")

        let first = files[0]
        app.player.send(.chooseSubtitles(.addon(first.id)))
        let track = try await app.player.until(timeout: .seconds(30), onTimeout: Failure.timedOut("subtitle track \(first.id.key)")) { state in
            guard let session = state.session, session.subtitleChoice == .addon(first.id) else { return Probe<MediaTrack, Failure>.pending }
            return session.tracks.first { $0.externalFile == first.url }.map(Probe.done) ?? .pending
        }
        result.playedSubtitle = "\(first.id.key) as track \(track.id.number)"
        Log.smoke.info("SMOKE subtitles playing: \(result.playedSubtitle ?? "")")
    }
}
