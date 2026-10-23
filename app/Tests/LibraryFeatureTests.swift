import Foundation
import Testing

struct LibraryFeatureTests {
    private let all = LibraryFeature.defaultFilter
    private let series = LibraryFilter(type: .series, sort: .name)

    private func contents(_ filter: LibraryFilter, _ titles: [MetaPreview], canLoadMore: Bool = false) -> LibraryContents {
        LibraryContents(filter: filter, types: [.movie, .series], titles: titles, canLoadMore: canLoadMore)
    }

    @Test func choosingAFilterLoadsItAndDropsContentsForAnotherOne() {
        let show = Fixture.preview("tt0944947", type: .series)
        var state = LibraryFeature.State.loading(all)
        #expect(LibraryFeature.reduce(&state, .select(.library(all))).isEmpty)
        #expect(LibraryFeature.reduce(&state, .select(.library(series))) == [.observe(series)])
        #expect(state == .loading(series))

        _ = LibraryFeature.reduce(&state, .contentsChanged(contents(all, [Fixture.preview("tt0111161")])))
        #expect(state == .loading(series))
        _ = LibraryFeature.reduce(&state, .contentsChanged(contents(series, [show])))
        #expect(state == .loaded(contents(series, [show])))
    }

    @Test func moreLoadsOnlyWhileTheLibraryHasMore() {
        var state = LibraryFeature.State.loading(all)
        #expect(LibraryFeature.reduce(&state, .loadMore).isEmpty)
        _ = LibraryFeature.reduce(&state, .contentsChanged(contents(all, [Fixture.preview("tt1")], canLoadMore: true)))
        #expect(LibraryFeature.reduce(&state, .loadMore) == [.loadMore])
        _ = LibraryFeature.reduce(&state, .contentsChanged(contents(all, [Fixture.preview("tt1")], canLoadMore: false)))
        #expect(LibraryFeature.reduce(&state, .loadMore).isEmpty)
    }

    @Test func pickingASourceListsItsTitlesNewestFirstAndYourLibraryAsBefore() {
        let source = SourceID("ab23cd45").require()
        let newest = SourceTitlesFilter(source: source, type: nil, sort: .recentlyAdded)
        var state = LibraryFeature.State.loaded(contents(all, []))

        #expect(LibraryFeature.reduce(&state, .pick(.yourLibrary)).isEmpty)
        #expect(LibraryFeature.reduce(&state, .pick(.source(source))) == [.listSource(newest, skip: 0)])
        #expect(state == .loadingSource(newest))
        #expect(state.listing.collection == .source(source))
        #expect(LibraryFeature.reduce(&state, .pick(.source(source))).isEmpty)

        _ = LibraryFeature.reduce(&state, .contentsChanged(contents(all, [Fixture.preview("tt1")])))
        #expect(state == .loadingSource(newest))
        _ = LibraryFeature.reduce(&state, .sourceListed(newest, skip: 0, .success(SourceTitlesPage(titles: [Fixture.preview("tt2")], hasMore: false))))
        #expect(state == .source(LibraryFeature.SourceTitles(filter: newest, titles: [Fixture.preview("tt2")], paging: .complete)))

        #expect(LibraryFeature.reduce(&state, .pick(.yourLibrary)) == [.observe(all)])
        #expect(state == .loading(all))
    }

    @Test func aSourcesTypeAndSortListItAgainAndDropAnswersForTheOldFilter() {
        let source = SourceID("ab23cd45").require()
        let newest = SourceTitlesFilter(source: source, type: nil, sort: .recentlyAdded)
        let showsByName = SourceTitlesFilter(source: source, type: .series, sort: .name)
        var state = LibraryFeature.opening(.source(source)).state
        #expect(LibraryFeature.opening(.source(source)).effects == [.listSource(newest, skip: 0)])
        #expect(LibraryFeature.opening(.yourLibrary).state == .loading(all))
        #expect(LibraryFeature.opening(.yourLibrary).effects == [.observe(all)])

        #expect(LibraryFeature.reduce(&state, .select(.source(showsByName))) == [.listSource(showsByName, skip: 0)])
        _ = LibraryFeature.reduce(&state, .sourceListed(newest, skip: 0, .success(SourceTitlesPage(titles: [Fixture.preview("tt1")], hasMore: false))))
        #expect(state == .loadingSource(showsByName))
        _ = LibraryFeature.reduce(&state, .sourceListed(showsByName, skip: 0, .failure(.unreachable)))
        #expect(state == .sourceFailed(showsByName, .unreachable))

        #expect(LibraryFeature.reduce(&state, .retry) == [.listSource(showsByName, skip: 0)])
        #expect(state == .loadingSource(showsByName))
        #expect(LibraryFeature.reduce(&state, .retry).isEmpty)
    }

    @Test func aSourcePagesInOnePageAtATimeWithEachTitleOnce() {
        let filter = SourceTitlesFilter(source: SourceID("ab23cd45").require(), type: .movie, sort: .name)
        let first = (1...100).map { Fixture.preview("tt\($0)") }
        var state = LibraryFeature.State.loadingSource(filter)
        _ = LibraryFeature.reduce(&state, .sourceListed(filter, skip: 0, .success(SourceTitlesPage(titles: first, hasMore: true))))

        #expect(LibraryFeature.reduce(&state, .loadMore) == [.listSource(filter, skip: 100)])
        #expect(LibraryFeature.reduce(&state, .loadMore).isEmpty)
        _ = LibraryFeature.reduce(&state, .sourceListed(filter, skip: 0, .success(SourceTitlesPage(titles: [Fixture.preview("tt999")], hasMore: false))))
        _ = LibraryFeature.reduce(&state, .sourceListed(filter, skip: 100, .failure(.unreachable)))
        #expect(state == .source(LibraryFeature.SourceTitles(filter: filter, titles: first, paging: .more(skip: 100))))

        #expect(LibraryFeature.reduce(&state, .loadMore) == [.listSource(filter, skip: 100)])
        let second = SourceTitlesPage(titles: [Fixture.preview("tt100"), Fixture.preview("tt101")], hasMore: false)
        _ = LibraryFeature.reduce(&state, .sourceListed(filter, skip: 100, .success(second)))
        #expect(state == .source(LibraryFeature.SourceTitles(filter: filter, titles: first + [Fixture.preview("tt101")], paging: .complete)))
        #expect(LibraryFeature.reduce(&state, .loadMore).isEmpty)
        #expect(LibraryFeature.reduce(&state, .remove(MediaID("tt1").require())).isEmpty)
    }

    @Test func removingTakesOutAListedTitle() {
        let movie = Fixture.preview("tt0111161")
        var state = LibraryFeature.State.loaded(contents(all, [movie]))
        #expect(LibraryFeature.reduce(&state, .remove(movie.media)) == [.remove(movie)])
        #expect(LibraryFeature.reduce(&state, .remove(MediaID("tt9999999").require())).isEmpty)
        #expect(state == .loaded(contents(all, [movie])))
    }
}

struct CalendarFeatureTests {
    private let episode = UpcomingEpisode(
        show: Fixture.preview("tt0944947", type: .series), video: Fixture.episode, name: Redacted("Winter Is Coming"), released: .distantFuture
    )

    @Test func appearingReloadsAndKeepsTheEpisodesShownUntilTheAnswer() {
        var state = CalendarFeature.State.loading
        #expect(CalendarFeature.reduce(&state, .appeared) == [.load])
        _ = CalendarFeature.reduce(&state, .episodesChanged(.loaded([episode])))
        #expect(state == .loaded([episode]))

        #expect(CalendarFeature.reduce(&state, .appeared) == [.load])
        _ = CalendarFeature.reduce(&state, .episodesChanged(.loading))
        #expect(state == .loaded([episode]))
        _ = CalendarFeature.reduce(&state, .episodesChanged(.failed(.addonFailed(reason: "offline"))))
        #expect(state == .loaded([episode]))
        _ = CalendarFeature.reduce(&state, .episodesChanged(.loaded([])))
        #expect(state == .loaded([]))
    }

    @Test func aFailedFirstLoadShowsTheErrorAndRetries() {
        var state = CalendarFeature.State.loading
        _ = CalendarFeature.reduce(&state, .episodesChanged(.failed(.addonFailed(reason: "offline"))))
        #expect(state == .failed(.addonFailed(reason: "offline")))
        #expect(CalendarFeature.reduce(&state, .retry) == [.load])
        #expect(state == .loading)
        #expect(CalendarFeature.reduce(&state, .retry).isEmpty)
    }
}

struct ReleaseScheduleTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/New_York").require()
        return calendar
    }()

    /// Monday, 19 October 2026, 15:00 in New York.
    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 15)).require()
    }

    private func episode(_ number: Int, inDays days: Int, hour: Int = 21) -> UpcomingEpisode {
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: today)).require()
        return UpcomingEpisode(
            show: Fixture.preview("tt0944947", type: .series),
            video: PlayableID("tt0944947:1:\(number)").require(),
            name: Redacted("Episode \(number)"),
            released: calendar.date(bySettingHour: hour, minute: 30, second: 0, of: day).require()
        )
    }

    @Test func daysAreLabeledByHowFarOffTheyAre() {
        let offsets = [0, 1, 2, 13, 14, 59, 60, 92]
        let episodes = offsets.enumerated().map { episode($0.offset + 1, inDays: $0.element) }

        let days = ReleaseSchedule.days(episodes, today: today, calendar: calendar)

        #expect(days.map(\.label) == [
            "Today", "Tomorrow", "In 2 days (Wednesday)", "In 13 days (Sunday)", "In 2 weeks (Monday)",
            "In 8 weeks (Thursday)", "In 2 months (Friday, December 18)", "In 3 months (Tuesday, January 19)",
        ])
    }

    @Test func episodesGroupByLocalDayFromTodayOn() {
        let lateTonight = episode(2, inDays: 0, hour: 23)
        let earlierToday = episode(1, inDays: 0, hour: 9)
        let tomorrow = episode(3, inDays: 1)

        let days = ReleaseSchedule.days([episode(9, inDays: -1), earlierToday, lateTonight, tomorrow], today: today, calendar: calendar)

        #expect(days.map(\.episodes) == [[earlierToday, lateTonight], [tomorrow]])
        #expect(days.first?.day == calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)))
    }
}
