import Testing

struct PlayerFeatureTests {
    private func playing(position: Duration = .zero, reportedSecond: Int64? = nil) -> PlayerFeature.State {
        var session = PlayerFeature.Session(candidate: Fixture.candidate())
        session.phase = .playing
        session.position = position
        session.duration = .seconds(100)
        session.reportedSecond = reportedSecond
        return .active(session)
    }

    @Test func openingAPlayableCandidateBeginsPlayback() {
        var state = PlayerFeature.State.idle
        let effects = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        #expect(effects == [.begin(Fixture.candidate(), Fixture.source)])
        #expect(state.statusLine == "0:00:00 / 0:00:00 · opening")
    }

    @Test func openingAnUnsupportedCandidateFailsWithoutTouchingTheEngine() {
        var state = PlayerFeature.State.idle
        let candidate = Fixture.candidate(.unsupported(kind: "Torrent"))
        #expect(PlayerFeature.reduce(&state, .open(candidate)).isEmpty)
        #expect(state == .failed(candidate, .unsupported(kind: "Torrent")))
    }

    @Test func progressIsReportedOncePerWholeSecond() {
        var state = playing(position: .seconds(12.2), reportedSecond: 12)
        #expect(PlayerFeature.reduce(&state, .engine(.position(.seconds(12.9)))).isEmpty)
        #expect(PlayerFeature.reduce(&state, .engine(.position(.seconds(13)))) == [.report(.progress(.seconds(13), of: .seconds(100)))])
        #expect(state.session?.reportedSecond == 13)
    }

    @Test func progressWaitsForTheDuration() {
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        #expect(PlayerFeature.reduce(&state, .engine(.position(.seconds(1)))).isEmpty)
        _ = PlayerFeature.reduce(&state, .engine(.duration(.seconds(60))))
        #expect(PlayerFeature.reduce(&state, .engine(.position(.seconds(1)))) == [.report(.progress(.seconds(1), of: .seconds(60)))])
    }

    @Test func negativePositionsClampToZero() {
        var state = playing()
        _ = PlayerFeature.reduce(&state, .engine(.position(.seconds(-0.04))))
        #expect(state.session?.position == .zero)
    }

    @Test func pauseFollowsTheEngineNotTheRequest() {
        var state = playing()
        #expect(PlayerFeature.reduce(&state, .togglePause) == [.setPaused(true)])
        #expect(state.session?.phase == .playing)
        #expect(PlayerFeature.reduce(&state, .engine(.paused(true))) == [.report(.paused(true))])
        #expect(state.session?.phase == .paused)
        #expect(PlayerFeature.reduce(&state, .togglePause) == [.setPaused(false)])
    }

    @Test func aStopWhileOpeningIsThePreviousFileMakingWay() {
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        _ = PlayerFeature.reduce(&state, .engine(.stopped))
        #expect(state.session?.phase == .opening)
        _ = PlayerFeature.reduce(&state, .engine(.loaded))
        _ = PlayerFeature.reduce(&state, .engine(.stopped))
        #expect(state == .idle)
    }

    @Test func endOfFileIsReported() {
        var state = playing()
        #expect(PlayerFeature.reduce(&state, .engine(.ended)) == [.report(.ended)])
        #expect(state.session?.phase == .ended)
    }

    @Test func engineFailureKeepsTheCandidate() {
        var state = playing()
        _ = PlayerFeature.reduce(&state, .engine(.failed(reason: "error: loading failed")))
        #expect(state == .failed(Fixture.candidate(), .failed(reason: "error: loading failed")))
        #expect(PlayerFeature.reduce(&state, .stop) == [.stop])
        #expect(state == .idle)
    }

    @Test func idleIgnoresEverythingButOpen() {
        var state = PlayerFeature.State.idle
        #expect(PlayerFeature.reduce(&state, .togglePause).isEmpty)
        #expect(PlayerFeature.reduce(&state, .stop).isEmpty)
        #expect(PlayerFeature.reduce(&state, .engine(.loaded)).isEmpty)
        #expect(state == .idle)
    }

    @Test func statusLineShowsTimePhaseVideoAndDecoder() {
        var state = playing(position: .seconds(3_725))
        _ = PlayerFeature.reduce(&state, .engine(.videoSize(VideoSize(width: 1920, height: 1080))))
        _ = PlayerFeature.reduce(&state, .engine(.hardwareDecoder("videotoolbox")))
        #expect(state.statusLine == "1:02:05 / 0:01:40 · playing · 1920×1080 · hwdec videotoolbox")
    }
}
