import Foundation
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
        #expect(effects == [.begin(Fixture.candidate(), Fixture.source, from: .zero)])
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
        _ = PlayerFeature.reduce(&state, .engine(.decoder("VideoToolbox HEVC (HW)")))
        #expect(state.statusLine == "1:02:05 / 0:01:40 · playing · 1920×1080 · VideoToolbox HEVC (HW)")
    }

    @Test func subtitlesShowForTheSession() {
        var state = playing()
        let line = SubtitleCue.text(SubtitleText("Get busy living,\nor get busy dying."))
        #expect(PlayerFeature.reduce(&state, .engine(.subtitles([line]))).isEmpty)
        #expect(state.session?.subtitles == [line])
    }

    @Test func aNewLoadStartsWithoutSubtitles() {
        var state = playing()
        _ = PlayerFeature.reduce(&state, .engine(.subtitles([.text(SubtitleText("Hope is a good thing."))])))
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        #expect(state == .active(PlayerFeature.Session(candidate: Fixture.candidate())))
    }

    @Test func subtitlesWithoutASessionAreDropped() {
        var state = PlayerFeature.State.idle
        #expect(PlayerFeature.reduce(&state, .engine(.subtitles([.text(SubtitleText("Brooks was here"))]))).isEmpty)
        #expect(state == .idle)
        state = .failed(Fixture.candidate(), .failed(reason: "refused"))
        _ = PlayerFeature.reduce(&state, .engine(.subtitles([.text(SubtitleText("So was Red"))])))
        #expect(state == .failed(Fixture.candidate(), .failed(reason: "refused")))
    }
}

struct PlayerTimelineTests {
    private let start = ContinuousClock.now

    private func playing(at position: Duration = .seconds(50), seekStep: SeekStep = .ten) -> PlayerFeature.State {
        var session = PlayerFeature.Session(candidate: Fixture.candidate())
        session.seekStep = seekStep
        session.phase = .playing
        session.position = position
        session.duration = .seconds(100)
        return .active(session)
    }

    private func scanning(_ direction: PlayerFeature.Direction, at position: Duration = .seconds(50)) -> PlayerFeature.State {
        var state = playing(at: position)
        _ = PlayerFeature.reduce(&state, .timeline(.hold(direction)))
        return state
    }

    private func step(_ direction: PlayerFeature.Direction, after seconds: Double, in state: inout PlayerFeature.State) -> [PlayerFeature.Effect] {
        PlayerFeature.reduce(&state, .timeline(.step(direction, at: start + .seconds(seconds))))
    }

    @Test func tapsInQuickSuccessionJumpFurtherUpToAMinute() {
        var state = playing()
        let jumps = [0, 0.5, 1, 1.5, 2, 2.5, 3].map { step(.forward, after: $0, in: &state) }
        #expect(jumps == [10, 20, 30, 40, 50, 60, 60].map { [.seek(by: .seconds($0))] })
    }

    @Test func aStreakGrowsByTheSeekStep() {
        var state = playing(seekStep: .thirty)
        let jumps = [0, 0.5, 1].map { step(.forward, after: $0, in: &state) }
        #expect(jumps == [30, 60, 60].map { [.seek(by: .seconds($0))] })
    }

    @Test func aJumpSkipsOneSeekStep() {
        var state = playing(seekStep: .fifteen)
        #expect(PlayerFeature.reduce(&state, .jump(.backward)) == [.seek(by: .seconds(-15))])
        #expect(PlayerFeature.reduce(&state, .jump(.forward)) == [.seek(by: .seconds(15))])
    }

    @Test func aStreakEndsAfterASecondOrOnATurn() {
        var state = playing()
        #expect(step(.backward, after: 0, in: &state) == [.seek(by: .seconds(-10))])
        #expect(step(.backward, after: 1, in: &state) == [.seek(by: .seconds(-20))])
        #expect(step(.backward, after: 2.1, in: &state) == [.seek(by: .seconds(-10))])
        #expect(step(.forward, after: 2.2, in: &state) == [.seek(by: .seconds(10))])
    }

    @Test func holdingPausesAndScansAtTwiceSpeed() {
        var state = playing()
        #expect(PlayerFeature.reduce(&state, .timeline(.hold(.forward))) == [.setPaused(true), .scanTick])
        #expect(state.session?.scan == PlayerFeature.Scan(direction: .forward, rate: .times2, position: .seconds(50)))
    }

    @Test func eachTickMovesThePlayheadByTheRate() {
        var state = scanning(.forward)
        #expect(PlayerFeature.reduce(&state, .timeline(.tick)) == [.seekTo(.seconds(50.5)), .scanTick])
        _ = PlayerFeature.reduce(&state, .timeline(.hold(.forward)))
        #expect(PlayerFeature.reduce(&state, .timeline(.tick)) == [.seekTo(.seconds(51.5)), .scanTick])
        #expect(state.session?.displayedPosition == .seconds(51.5))
        #expect(state.session?.position == .seconds(50))
    }

    @Test func pressingTheScansWaySpeedsItUpToThirtyTwoTimes() {
        var state = scanning(.backward)
        var rates: [PlayerFeature.ScanRate?] = []
        for _ in 0..<5 {
            #expect(step(.backward, after: 0, in: &state).isEmpty)
            rates.append(state.session?.scan?.rate)
        }
        #expect(rates == [.times4, .times8, .times16, .times32, .times32])
    }

    @Test func pressesAgainstTheScanSlowItDownThenResumePlayback() {
        var state = scanning(.forward)
        _ = PlayerFeature.reduce(&state, .timeline(.hold(.forward)))
        #expect(PlayerFeature.reduce(&state, .timeline(.hold(.backward))).isEmpty)
        #expect(state.session?.scan?.rate == .times2)
        #expect(step(.backward, after: 0, in: &state) == [.setPaused(false)])
        #expect(state.session?.scan == nil)
    }

    @Test func playPauseEndsTheScan() {
        var state = scanning(.forward)
        _ = PlayerFeature.reduce(&state, .engine(.paused(true)))
        #expect(PlayerFeature.reduce(&state, .togglePause) == [.setPaused(false)])
        #expect(state.session?.scan == nil)
    }

    @Test func rewindingPastTheStartSeeksThereAndResumes() {
        var state = scanning(.backward, at: .seconds(0.75))
        #expect(PlayerFeature.reduce(&state, .timeline(.tick)) == [.seekTo(.seconds(0.25)), .scanTick])
        #expect(PlayerFeature.reduce(&state, .timeline(.tick)) == [.seekTo(.zero), .setPaused(false)])
        #expect(state.session?.scan == nil)
    }

    @Test func aSeekDuringAScanEndsIt() {
        var state = scanning(.forward)
        #expect(PlayerFeature.reduce(&state, .jump(.forward)) == [.setPaused(false), .seek(by: .seconds(10))])
        #expect(state.session?.scan == nil)
    }

    @Test func ticksOutsideAScanAreIgnored() {
        var state = playing()
        #expect(PlayerFeature.reduce(&state, .timeline(.tick)).isEmpty)
        #expect(state == playing())
    }
}

struct PlayerControlsTests {
    private let english = MediaTrack(
        id: MediaTrack.ID(kind: .subtitle, number: 1), title: nil, language: "eng", codec: "subrip",
        channelCount: nil, isForced: false, externalFile: nil, isSelected: false
    )
    private let synced = AddonSubtitle(
        id: AddonSubtitle.ID(addon: Fixture.manifest, key: "synced-1"),
        url: URL(string: "https://subs.example/synced-1.srt").require(),
        language: "pol",
        label: "Synced"
    )
    private let intro = SkipSegment(kind: .intro, range: .seconds(60)..<(.seconds(90)), fit: .matched, confidence: 1)

    private func playing(at position: Duration = .zero) -> PlayerFeature.State {
        var session = PlayerFeature.Session(candidate: Fixture.candidate())
        session.phase = .playing
        session.position = position
        session.tracks = [english]
        session.segments = .loaded([intro])
        return .active(session)
    }

    @Test func onlyKnownUnselectedTracksAreSelected() {
        var state = playing()
        #expect(PlayerFeature.reduce(&state, .select(english.id)) == [.select(english.id)])
        #expect(PlayerFeature.reduce(&state, .select(MediaTrack.ID(kind: .subtitle, number: 9))).isEmpty)
        _ = PlayerFeature.reduce(&state, .engine(.tracks([english.selected])))
        #expect(PlayerFeature.reduce(&state, .select(english.id)).isEmpty)
    }

    @Test func anAddonSubtitleIsAddedOnceThenSelectedAsItsTrack() {
        var state = playing()
        let choice = PlayerFeature.SubtitleChoice.addon(synced.id)
        #expect(PlayerFeature.reduce(&state, .chooseSubtitles(choice)).isEmpty)

        let source = SubtitleSource(addon: Fixture.manifest, addonName: "Subtitle Sync", subtitles: .loaded([synced]))
        _ = PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(), [source]))
        #expect(PlayerFeature.reduce(&state, .chooseSubtitles(choice)) == [.addSubtitles(synced)])

        let added = MediaTrack(
            id: MediaTrack.ID(kind: .subtitle, number: 2), title: "Synced", language: "pol", codec: "subrip",
            channelCount: nil, isForced: false, externalFile: synced.url, isSelected: true
        )
        _ = PlayerFeature.reduce(&state, .engine(.tracks([english, added])))
        #expect(state.session?.subtitleChoice == choice)
        #expect(state.session?.builtInSubtitles == [english])
        #expect(PlayerFeature.reduce(&state, .chooseSubtitles(choice)).isEmpty)

        _ = PlayerFeature.reduce(&state, .engine(.tracks([english.selected, added.unselected])))
        #expect(state.session?.subtitleChoice == .builtIn(english.id))
        #expect(PlayerFeature.reduce(&state, .chooseSubtitles(choice)) == [.select(added.id)])
        #expect(PlayerFeature.reduce(&state, .chooseSubtitles(.off)) == [.turnOffSubtitles])
    }

    @Test func subtitlesForAnotherCandidateAreDropped() {
        var state = playing()
        let source = SubtitleSource(addon: Fixture.manifest, addonName: "Subtitle Sync", subtitles: .loaded([synced]))
        _ = PlayerFeature.reduce(&state, .subtitlesFound(Fixture.candidate(index: 1), [source]))
        #expect(state.session?.addonSubtitles == [])
    }

    @Test func theSeekStepReadForThisCandidateApplies() {
        var state = playing()
        #expect(PlayerFeature.reduce(&state, .preferencesRead(Fixture.candidate(), .thirty)).isEmpty)
        #expect(state.session?.seekStep == .thirty)
    }

    @Test func aSeekStepReadForAnotherCandidateIsDropped() {
        var state = playing()
        #expect(PlayerFeature.reduce(&state, .preferencesRead(Fixture.candidate(index: 1), .thirty)).isEmpty)
        #expect(state.session?.seekStep == .ten)
    }

    @Test func speedChangesOnlyWhenDifferent() {
        var state = playing()
        #expect(PlayerFeature.reduce(&state, .setSpeed(.normal)).isEmpty)
        #expect(PlayerFeature.reduce(&state, .setSpeed(.oneAndAHalf)) == [.setSpeed(.oneAndAHalf)])
        _ = PlayerFeature.reduce(&state, .engine(.speed(.oneAndAHalf)))
        #expect(state.session?.speed == .oneAndAHalf)
    }

    @Test func segmentsAreLookedUpOnceTheDurationIsKnown() {
        var state = PlayerFeature.State.idle
        _ = PlayerFeature.reduce(&state, .open(Fixture.candidate()))
        #expect(PlayerFeature.reduce(&state, .engine(.duration(.seconds(3_000)))) == [.findSegments(Fixture.movie, duration: .seconds(3_000))])
        #expect(PlayerFeature.reduce(&state, .engine(.duration(.seconds(3_001)))).isEmpty)
    }

    @Test func skippingJumpsToTheEndOfTheSegmentPlayingNow() {
        var state = playing(at: .seconds(70))
        #expect(state.activeSegment == intro)
        #expect(PlayerFeature.reduce(&state, .skip(intro)) == [.seekTo(.seconds(90))])
        state = playing(at: .seconds(95))
        #expect(state.activeSegment == nil)
    }

    @Test func playbackStartsFromTheRequestedPosition() {
        var state = PlayerFeature.State.idle
        let effects = PlayerFeature.reduce(&state, .open(Fixture.candidate(), from: .seconds(600)))
        #expect(effects == [.begin(Fixture.candidate(), Fixture.source, from: .seconds(600))])
    }
}

private extension MediaTrack {
    var unselected: MediaTrack {
        MediaTrack(id: id, title: title, language: language, codec: codec, channelCount: channelCount,
                   isForced: isForced, externalFile: externalFile, isSelected: false)
    }

    var selected: MediaTrack {
        MediaTrack(id: id, title: title, language: language, codec: codec, channelCount: channelCount,
                   isForced: isForced, externalFile: externalFile, isSelected: true)
    }
}
